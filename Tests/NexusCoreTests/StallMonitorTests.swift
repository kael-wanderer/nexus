import Foundation
import os
import Testing
@testable import NexusCore

/// `Thread.sleep` is unavailable from async code; this is the one place a test blocks on purpose.
@MainActor private func blockMainThread(for seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
}

struct StallMonitorTests {
    @Test("A main thread blocked for 120 ms is reported as a stall of at least the threshold")
    @MainActor func reportsAStall() async throws {
        let stalls = OSAllocatedUnfairLock<[Duration]>(initialState: [])
        let monitor = StallMonitor(report: { d in stalls.withLock { $0.append(d) } })
        monitor.start()
        defer { monitor.stop() }
        try await Task.sleep(for: .milliseconds(50))
        blockMainThread(for: 0.12)
        try await waitUntil { stalls.withLock { !$0.isEmpty } }
        #expect(stalls.withLock { $0.first ?? .zero } >= .milliseconds(32))
    }

    @Test("Only the exact value 1 switches it on")
    func requestedOnlyByOne() {
        #expect(StallMonitor.isRequested(["NEXUS_STALL_LOG": "1"]))
        #expect(!StallMonitor.isRequested(["NEXUS_STALL_LOG": "true"]))
        #expect(!StallMonitor.isRequested([:]))
    }
}
