import CoreGraphics
import Foundation
import ScreenCaptureKit

public protocol WindowPreviewing: Sendable {
    func preview(for window: WindowIdentity, maxDimension: CGFloat) async -> SendableImage?
    func invalidate(_ window: WindowIdentity) async

    /// Every thumbnail for one grid, delivered as each lands rather than all at the end (M25).
    /// One `SCShareableContent` fetch serves the whole batch: it is the expensive part of a capture,
    /// and paying it per window is what made the grid unusable at twelve.
    func previews(
        for windows: [WindowIdentity],
        maxDimension: CGFloat
    ) async -> AsyncStream<(WindowIdentity, SendableImage)>
}

/// Runs a batch with a ceiling on how much of it happens at once.
///
/// A grid of twenty windows asking ScreenCaptureKit for twenty captures at the same moment is
/// slower than four at a time, not faster: the work is one compositor's, and the queue is where
/// it ends up either way (M25).
enum PreviewBatch {
    static func run<T: Sendable>(
        _ items: [T],
        maxInFlight: Int,
        work: @Sendable @escaping (T) async -> Void
    ) async {
        guard !items.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            let limit = max(1, min(maxInFlight, items.count))
            while next < limit {
                let item = items[next]
                group.addTask { await work(item) }
                next += 1
            }
            while await group.next() != nil {
                guard next < items.count else { continue }
                let item = items[next]
                group.addTask { await work(item) }
                next += 1
            }
        }
    }
}

/// `CGImage` is not `Sendable`. This is the one audited place where one crosses an isolation
/// boundary: it is produced by ScreenCaptureKit, never mutated, and only read.
public struct SendableImage: @unchecked Sendable {
    public let image: CGImage
    public init(_ image: CGImage) { self.image = image }
}

/// Window thumbnails, captured lazily on hover and never on a schedule. Entirely optional: with
/// Screen Recording denied every call returns `nil` and the flyout shows titles only.
public actor WindowPreviewService: WindowPreviewing {
    private struct Entry {
        let image: SendableImage
        let capturedAt: Date
    }

    private static let timeToLive: TimeInterval = 5
    // A grid holds more windows than a flyout ever did (§5).
    private static let maximumEntries = 64
    private static let maximumInFlight = 4

    private var cache: [CGWindowID: Entry] = [:]
    private var inFlight: Set<CGWindowID> = []

    public init() {}

    public func invalidate(_ window: WindowIdentity) {
        cache[window.number] = nil
    }

    public func invalidateAll() {
        cache.removeAll()
    }

    public func preview(for window: WindowIdentity, maxDimension: CGFloat) async -> SendableImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }

        if let entry = cache[window.number], Date().timeIntervalSince(entry.capturedAt) < Self.timeToLive {
            return entry.image
        }
        guard !inFlight.contains(window.number) else { return cache[window.number]?.image }
        inFlight.insert(window.number)
        defer { inFlight.remove(window.number) }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let target = content.windows.first(where: { $0.windowID == window.number }) else {
                // Not an error: a window that is off-screen, on another Space, or carries a
                // synthetic id because AX gave it none, has nothing to capture.
                Log.windows.notice(
                    "No capturable window \(window.number, privacy: .public) for \(window.owner.bundleIdentifier, privacy: .public)"
                )
                return nil
            }
            guard let image = await Self.capture(target, maxDimension: maxDimension) else { return nil }
            store(image, for: window.number)
            return image
        } catch {
            // A denial or a window that vanished mid-capture is a normal state change (§3.5),
            // never an alert — but it is a state change, so it is `.notice`, not `.debug` (D48).
            Log.windows.notice("Preview unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Every thumbnail for one grid (§5). Cached windows are answered before anything is
    /// fetched — reopening the switcher twice in five seconds should cost nothing at all — and
    /// the stream always finishes, on every path, so a caller's `for await` loop is guaranteed
    /// to end even when Screen Recording is denied, everything was cached, or the fetch throws.
    public func previews(
        for windows: [WindowIdentity],
        maxDimension: CGFloat
    ) async -> AsyncStream<(WindowIdentity, SendableImage)> {
        let (stream, continuation) = AsyncStream<(WindowIdentity, SendableImage)>.makeStream()

        guard CGPreflightScreenCaptureAccess() else {
            continuation.finish()
            return stream
        }

        var pending: [WindowIdentity] = []
        for window in windows {
            if let entry = cache[window.number], Date().timeIntervalSince(entry.capturedAt) < Self.timeToLive {
                continuation.yield((window, entry.image))
            } else {
                pending.append(window)
            }
        }
        guard !pending.isEmpty else {
            continuation.finish()
            return stream
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // A denial, or a fetch that raced a display change: normal state, never an alert (D48).
            Log.windows.notice("Bulk previews unavailable: \(String(describing: error), privacy: .public)")
            continuation.finish()
            return stream
        }

        let targets = pending.compactMap { identity -> CaptureTarget? in
            guard let window = content.windows.first(where: { $0.windowID == identity.number }) else { return nil }
            return CaptureTarget(identity: identity, window: window)
        }

        Task { [weak self] in
            guard let self else {
                continuation.finish()
                return
            }
            await PreviewBatch.run(targets, maxInFlight: Self.maximumInFlight) { target in
                guard let image = await Self.capture(target.window, maxDimension: maxDimension) else { return }
                await self.store(image, for: target.identity.number)
                continuation.yield((target.identity, image))
            }
            continuation.finish()
        }
        return stream
    }

    /// `SCWindow` is not `Sendable`; this crosses the same audited boundary as `SendableImage`
    /// above, carrying a fetch result into the capped task group untouched and unread.
    private struct CaptureTarget: @unchecked Sendable {
        let identity: WindowIdentity
        let window: SCWindow
    }

    private static func capture(_ window: SCWindow, maxDimension: CGFloat) async -> SendableImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = min(1, maxDimension / max(CGFloat(window.frame.width), CGFloat(window.frame.height), 1))
        configuration.width = max(1, Int(CGFloat(window.frame.width) * scale))
        configuration.height = max(1, Int(CGFloat(window.frame.height) * scale))
        configuration.showsCursor = false
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return SendableImage(image)
        } catch {
            // Same normal-state logging as the single-window path (§3.5, D48); one capture
            // failing inside a batch does not stop the rest.
            Log.windows.notice("Preview unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func store(_ image: SendableImage, for identifier: CGWindowID) {
        if cache.count >= Self.maximumEntries {
            let oldest = cache.min { $0.value.capturedAt < $1.value.capturedAt }?.key
            if let oldest { cache[oldest] = nil }
        }
        cache[identifier] = Entry(image: image, capturedAt: Date())
    }
}
