import Foundation

// Ported from Bugler (`Sources/Bugler/Core/RemoteJSON.swift`), same author. The update feed is
// the only thing Nexus reads from off the machine, so its body is bounded in size, in time and in
// nesting before anything parses it.

/// Bounds on JSON that arrived over the network, checked before it is parsed.
///
/// A deeply nested document overflows the stack inside `JSONDecoder`, and a stack overflow is not
/// an error `try?` can catch: the process dies. The update feed nests two levels; anything past 32
/// is not a shape Nexus has a reading for.
public enum RemoteJSON {
    public static let maxDepth = 32
    /// The feed is a few hundred bytes. 64 KB is generous and still nothing to hold.
    public static let maxBytes = 64 * 1024

    /// Whether `data` is worth handing to a parser. Counts bracket depth over the raw bytes, with
    /// no recursion; bytes inside a string literal are skipped, and `\` consumes the byte after it.
    public static func isAcceptable(
        _ data: Data, maxDepth: Int = RemoteJSON.maxDepth, maxBytes: Int = RemoteJSON.maxBytes
    ) -> Bool {
        guard !data.isEmpty, data.count <= maxBytes else { return false }
        var depth = 0
        var inString = false
        var escaped = false
        for byte in data {
            if escaped {
                escaped = false
                continue
            }
            if inString {
                switch byte {
                case UInt8(ascii: "\\"): escaped = true
                case UInt8(ascii: "\""): inString = false
                default: break
                }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                if depth > maxDepth { return false }
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth = max(0, depth - 1)
            default: break
            }
        }
        return true
    }
}

/// How much of a response body has been taken, and whether the next piece fits. Asked *before* a
/// chunk is appended, because a bound checked after the fact already holds the bytes it refuses.
public struct BodyBudget: Equatable, Sendable {
    public let limit: Int
    public private(set) var used = 0

    public init(limit: Int) { self.limit = limit }

    public func admits(_ count: Int) -> Bool { used + count <= limit }

    /// A negative length means the server announced none; the per-chunk bound handles that.
    public func admits(announcedLength: Int64) -> Bool {
        announcedLength < 0 || admits(Int(clamping: announcedLength))
    }

    @discardableResult
    public mutating func take(_ count: Int) -> Bool {
        guard admits(count) else { return false }
        used += count
        return true
    }
}

/// Reads a response body and stops the transfer the moment it would exceed the limit.
/// `URLSession.data(for:)` would read the whole body first, however long.
private final class BoundedBody: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var budget: BodyBudget
    private var body = Data()
    private var response: HTTPURLResponse?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse)?, Never>?
    private var finished = false

    init(limit: Int) {
        budget = BodyBudget(limit: limit)
    }

    func read(request: URLRequest, configuration: URLSessionConfiguration) async
        -> (Data, HTTPURLResponse)?
    {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        // The session holds its delegate strongly until invalidated.
        defer { session.finishTasksAndInvalidate() }
        return await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            session.dataTask(with: request).resume()
        }
    }

    /// Resumes exactly once: finished, failed, or cancelled for size.
    private func finish(_ result: (Data, HTTPURLResponse)?) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation?.resume(returning: result)
        continuation = nil
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        self.response = response as? HTTPURLResponse
        let admits = budget.admits(announcedLength: response.expectedContentLength)
        lock.unlock()
        completionHandler(admits ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let fits = budget.take(data.count)
        if fits { body.append(data) }
        lock.unlock()
        guard !fits else { return }
        dataTask.cancel()
        finish(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let result: (Data, HTTPURLResponse)?
        if error == nil, let response { result = (body, response) } else { result = nil }
        lock.unlock()
        finish(result)
    }

    /// Never follow a redirect away from https.
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}

public enum RemoteFetch {
    /// `URLRequest.timeoutInterval` is an idle timeout; this bounds the whole transfer.
    public static let resourceTimeout: TimeInterval = 20

    public static let configuration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return configuration
    }()

    /// The body, or `nil` if the request failed, was refused, or ran past `limit`.
    public static func body(
        for request: URLRequest, limit: Int = RemoteJSON.maxBytes,
        configuration: URLSessionConfiguration = RemoteFetch.configuration
    ) async -> (Data, HTTPURLResponse)? {
        await BoundedBody(limit: limit).read(request: request, configuration: configuration)
    }
}
