import Foundation
import Testing

@testable import NexusCore

@Suite("Script runner")
struct ScriptRunnerTests {
    @Test("Numbers and booleans come back in order")
    func values() async {
        #expect(await AppleScriptRunner().run("return {1.5, 240, true}") == .values([1.5, 240, 1]))
    }

    @Test("A script that fails is reported as failed")
    func failure() async {
        #expect(await AppleScriptRunner().run("error number -128") == .failed)
    }

    @Test("Error -1712 is a timeout")
    func timeout() async {
        #expect(await AppleScriptRunner().run("error number -1712") == .timedOut)
    }

    @Test("A script that returns nothing is empty")
    func empty() async {
        #expect(await AppleScriptRunner().run("return") == .empty)
    }

    @Test("A script that blocks its thread does not block the main actor")
    @MainActor func mainActorStaysFree() async {
        // A stand-in that blocks for 0.4 s. A slow *real* script cannot be used here: the test
        // host pumps its main thread with a bare CFRunLoop, where a long-running NSAppleScript
        // waits for an event loop that never comes. In the app (NSApplication) it runs fine.
        let runner = AppleScriptRunner(executor: { _ in
            Thread.sleep(forTimeInterval: 0.4)
            return .values([1])
        })
        async let outcome = runner.run("anything")
        var ticks = 0
        let start = ContinuousClock.now
        while ContinuousClock.now - start < .milliseconds(300) {
            try? await Task.sleep(for: .milliseconds(10))
            ticks += 1
        }
        #expect(ticks >= 5)  // blocked, it would be 0 or 1; 30 when idle
        #expect(await outcome == .values([1]))
    }
}
