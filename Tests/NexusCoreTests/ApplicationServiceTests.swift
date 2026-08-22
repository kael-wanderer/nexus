import AppKit
import Foundation
import Testing

@testable import NexusCore

@Suite("ApplicationService")
struct ApplicationServiceTests {
    @Test("Finder resolves from its bundle identifier without being launched")
    func resolvesInstalledApplication() async {
        let service = ApplicationService()
        let finder = await service.application(for: ApplicationIdentity(bundleIdentifier: "com.apple.finder"))
        #expect(finder != nil)
        #expect(finder?.bundleURL.pathExtension == "app")
    }

    @Test("An unknown bundle identifier resolves to nil rather than throwing")
    func unknownApplication() async {
        let service = ApplicationService()
        let missing = await service.application(for: ApplicationIdentity(bundleIdentifier: "com.example.definitely-not-installed"))
        #expect(missing == nil)
    }

    @Test("Launching an unknown application throws notFound instead of hanging")
    func launchUnknown() async {
        let service = ApplicationService()
        await #expect(throws: NexusError.notFound) {
            try await service.launch(ApplicationIdentity(bundleIdentifier: "com.example.definitely-not-installed"))
        }
    }

    @Test("Quitting an application that is not running reports the target as gone")
    func quitNotRunning() async {
        let service = ApplicationService()
        await #expect(throws: NexusError.targetDisappeared) {
            try await service.quit(ApplicationIdentity(bundleIdentifier: "com.example.definitely-not-installed"), force: false)
        }
    }

    @Test("Running applications are reported with running state and a bundle URL")
    func runningApplications() async {
        let service = ApplicationService()
        let running = await service.runningApplications()
        // Finder is always running on a live macOS session.
        #expect(running.contains { $0.identity.bundleIdentifier == "com.apple.finder" })
        let allRunning = running.allSatisfy(\.isRunning)
        let allNamed = running.allSatisfy { !$0.name.isEmpty }
        #expect(allRunning)
        #expect(allNamed)
    }

    @Test("Pushed window counts and the active application appear on the next read")
    func pushedState() async {
        let service = ApplicationService()
        let finderPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.finder")
            .first?
            .processIdentifier
        guard let finderPID else { return }

        await service.updateWindowCounts([finderPID: 7])
        await service.updateActiveApplication("com.apple.finder")

        let finder = await service.runningApplications()
            .first { $0.identity.bundleIdentifier == "com.apple.finder" }
        #expect(finder?.windowCount == 7)
        #expect(finder?.isActive == true)
    }
}

@Suite("WindowCounts")
struct WindowCountsTests {
    @Test("Counts come back without any permission and are all positive")
    func counts() {
        let counts = WindowCounts.byProcess()
        #expect(counts.values.allSatisfy { $0 > 0 })
    }

    @Test("Window numbers for a process are a subset of that process's count")
    func windowNumbers() {
        let counts = WindowCounts.byProcess()
        guard let (pid, count) = counts.first else { return }
        #expect(WindowCounts.windowNumbers(for: pid).count == count)
    }

    @Test("An unused pid has no windows")
    func unknownProcess() {
        #expect(WindowCounts.byProcess()[-1] == nil)
        #expect(WindowCounts.windowNumbers(for: -1).isEmpty)
    }
}
