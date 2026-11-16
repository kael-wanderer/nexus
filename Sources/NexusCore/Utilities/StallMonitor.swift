import Dispatch
import Foundation
import os

/// A number for "the bar felt stuck". A timer on a private queue pings the main queue every
/// `interval`; a ping answered `threshold` or more late is one stall, reported with its length.
/// Only one ping is in flight at a time, so a single stall is a single report.
public final class StallMonitor: Sendable {
    public static let environmentKey = "NEXUS_STALL_LOG"

    private struct State {
        var timer: DispatchSourceTimer?
        var outstanding = false
    }

    private let threshold: Duration
    private let interval: Duration
    private let report: @Sendable (Duration) -> Void
    private let queue = DispatchQueue(label: "com.congbui.nexus.stall-monitor", qos: .utility)
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// `report` runs off the main thread, once per stall at or above `threshold`.
    public init(
        threshold: Duration = .milliseconds(32),
        interval: Duration = .milliseconds(8),
        report: @escaping @Sendable (Duration) -> Void
    ) {
        self.threshold = threshold
        self.interval = interval
        self.report = report
    }

    public func start() {
        state.withLock { state in
            guard state.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + interval.timeInterval, repeating: interval.timeInterval)
            timer.setEventHandler { [weak self] in self?.ping() }
            state.timer = timer
            timer.resume()
        }
    }

    public func stop() {
        state.withLock { state in
            state.timer?.cancel()
            state.timer = nil
            state.outstanding = false
        }
    }

    /// True only when the variable is exactly `1`.
    public static func isRequested(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[environmentKey] == "1"
    }

    private func ping() {
        let proceed = state.withLock { state -> Bool in
            guard state.timer != nil, !state.outstanding else { return false }
            state.outstanding = true
            return true
        }
        guard proceed else { return }
        let sent = ContinuousClock.now
        DispatchQueue.main.async { [weak self] in
            let late = ContinuousClock.now - sent
            guard let self else { return }
            state.withLock { $0.outstanding = false }
            guard late >= threshold else { return }
            queue.async { [report] in report(late) }
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
