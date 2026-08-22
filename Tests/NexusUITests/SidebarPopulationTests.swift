import Foundation
import NexusCore
import Testing

@testable import NexusUI

@MainActor
private func makeSidebar(
    running: [NexusApplication],
    pinned: [String] = [],
    showRunning: Bool = true
) -> (SidebarViewModel, ConfigurationController) {
    var initial = NexusConfiguration()
    initial.pinnedApplications = pinned
    initial.behavior.showRunningApplications = showRunning
    initial.onboarding.hasCompleted = true
    let configuration = ConfigurationController(
        store: InMemoryConfigurationStore(initial),
        events: EventBus(),
        saveDelay: .zero
    )
    let model = SidebarViewModel(
        applications: FakeApplicationService(running),
        configuration: configuration,
        events: EventBus()
    )
    return (model, configuration)
}

private func runningApps(_ count: Int) -> [NexusApplication] {
    (0..<count).map { makeApplication("com.example.app\($0)", name: "App \($0)", running: true) }
}

/// Milestone 3 verified that launch/quit *events* move the sidebar. These cover the other half:
/// what the sidebar shows the instant it starts, before any event has fired.
@Suite("Sidebar initial population")
@MainActor
struct SidebarPopulationTests {
    @Test("start() populates every already-running application without waiting for an event")
    func startPopulates() async throws {
        let (model, _) = makeSidebar(running: runningApps(25))
        #expect(model.running.isEmpty)

        model.start()
        defer { model.stop() }
        for _ in 0..<200 where model.running.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.running.count == 25)
        #expect(model.sectionRowCounts == [0, 25])
    }

    @Test("Applications already running at launch are not swallowed by the pinned filter")
    func pinnedAndRunningSplit() async {
        let (model, _) = makeSidebar(
            running: runningApps(5),
            pinned: ["com.example.app0", "com.example.app1"]
        )
        await model.refresh()
        #expect(model.pinned.count == 2)
        #expect(model.running.count == 3)
        // Every running application is accounted for in exactly one section.
        let shown = Set(model.pinned.map(\.id)).union(model.running.map(\.id))
        #expect(shown.count == 5)
    }

    @Test("showRunningApplications = false hides the section — the state that looked like a bug")
    func showRunningDisabled() async {
        let (model, _) = makeSidebar(
            running: runningApps(25),
            pinned: ["com.apple.calculator"],
            showRunning: false
        )
        await model.refresh()
        #expect(model.running.count == 24 || model.running.count == 25)
        // The rows the panel actually lays out collapse to the pinned section alone.
        #expect(model.sectionRowCounts == [model.pinned.count])
    }

    @Test("Turning the section back on restores the rows without a relaunch")
    func toggleBackOn() async {
        let (model, configuration) = makeSidebar(running: runningApps(4), showRunning: false)
        await model.refresh()
        #expect(model.sectionRowCounts == [0])

        configuration.update { $0.behavior.showRunningApplications = true }
        #expect(model.sectionRowCounts == [0, 4])
    }

    @Test("A clean configuration shows running applications by default")
    func defaultShowsRunning() {
        #expect(NexusConfiguration().behavior.showRunningApplications)
    }

    @Test("Many running applications still produce a frame that fits the screen")
    func tallListIsClampedToTheScreen() {
        var appearance = AppearanceConfiguration()
        appearance.iconSize = 40
        appearance.iconSpacing = 8
        let visible = CGRect(x: 0, y: 85, width: 2_560, height: 1_325)

        let size = SidebarLayout.size(
            sectionRowCounts: [0, 25, 1],
            appearance: appearance,
            expanded: false
        )
        #expect(size.height > visible.height)

        let frame = SidebarLayout.frame(
            size: size, in: visible, position: .left, hidden: false
        )
        #expect(visible.contains(frame))
    }
}
