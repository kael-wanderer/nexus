import AppKit
import Foundation

/// What a script came to. Numbers and booleans only: nothing here carries a track name.
public enum ScriptOutcome: Sendable, Equatable {
    /// Numbers and booleans (true = 1, false = 0), in order.
    case values([Double])
    /// Ran, returned nothing usable.
    case empty
    /// AppleScript error -1712: the target did not answer in time.
    case timedOut
    /// Anything else.
    case failed
}

public protocol ScriptRunning: Sendable {
    func run(_ source: String) async -> ScriptOutcome
}

/// Runs AppleScript off the main actor.
///
/// `NSAppleScript` is documented as main-thread-only. Every instance here is created, compiled and
/// executed on one serial queue and nowhere else, which is the accepted trade for keeping a slow
/// player from freezing the bar (a script that waits on a busy app blocks its thread, not the UI).
public final class AppleScriptRunner: ScriptRunning, @unchecked Sendable {
    public static let timeoutSeconds = 2

    private static let cacheLimit = 32

    /// One queue for the whole process, not one per runner: two instances running at once is the
    /// same thread-safety problem as two threads, and the Apple Event machinery is process-wide.
    private static let queue = DispatchQueue(label: "com.congbui.nexus.script", qos: .utility)
    /// Compiled scripts by source. Touched only on `queue`.
    private var compiled: [String: NSAppleScript] = [:]

    /// Tests only: stands in for compile-and-execute, still on the shared queue.
    private let executor: (@Sendable (String) -> ScriptOutcome)?

    public init() { executor = nil }

    init(executor: @escaping @Sendable (String) -> ScriptOutcome) { self.executor = executor }

    public func run(_ source: String) async -> ScriptOutcome {
        await withCheckedContinuation { continuation in
            Self.queue.async { continuation.resume(returning: self.execute(source)) }
        }
    }

    /// Only ever called on the shared queue.
    private func execute(_ source: String) -> ScriptOutcome {
        if let executor { return executor(source) }
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            let wrapped = "with timeout of \(Self.timeoutSeconds) seconds\n\(source)\nend timeout"
            guard let fresh = NSAppleScript(source: wrapped) else { return .failed }
            if compiled.count >= Self.cacheLimit { compiled.removeAll() }
            compiled[source] = fresh
            script = fresh
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let number = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            // The number only: the dictionary can carry the track name. `.notice` because a
            // silently missing timeline is the class of bug that took three rebuilds to find (D66).
            Log.system.notice("Media script failed, error \(number, privacy: .public)")
            return number == -1712 ? .timedOut : .failed
        }
        return Self.outcome(of: result)
    }

    private static func outcome(of result: NSAppleEventDescriptor) -> ScriptOutcome {
        if result.numberOfItems > 0 {
            var values: [Double] = []
            for index in 1...result.numberOfItems {
                guard let item = result.atIndex(index) else { return .empty }
                values.append(number(of: item))
            }
            return .values(values)
        }
        if result.descriptorType == typeNull { return .empty }
        return .values([number(of: result)])
    }

    private static func number(of descriptor: NSAppleEventDescriptor) -> Double {
        switch descriptor.descriptorType {
        case DescType(typeTrue):
            return 1
        case DescType(typeBoolean) where descriptor.booleanValue:
            return 1
        case DescType(typeFalse), DescType(typeBoolean):
            return 0
        default:
            return descriptor.doubleValue
        }
    }
}
