import Foundation
import Testing

@testable import NexusCore

@Suite("Bulk previews")
struct WindowPreviewBatchTests {
    /// Counts how many pieces of work overlap, which is the only thing the cap promises.
    actor Concurrency {
        private var current = 0
        private(set) var peak = 0

        func enter() { current += 1; peak = max(peak, current) }
        func leave() { current -= 1 }
    }

    @Test("Never more than the cap in flight, and everything still runs")
    func capped() async {
        let counter = Concurrency()
        let done = Counter()

        await PreviewBatch.run(Array(1...20), maxInFlight: 4) { _ in
            await counter.enter()
            try? await Task.sleep(for: .milliseconds(5))
            await counter.leave()
            await done.increment()
        }

        #expect(await counter.peak <= 4)
        #expect(await done.value == 20)
    }

    @Test("An empty batch finishes immediately")
    func empty() async {
        let done = Counter()
        await PreviewBatch.run([Int](), maxInFlight: 4) { _ in await done.increment() }
        #expect(await done.value == 0)
    }

    actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }
}
