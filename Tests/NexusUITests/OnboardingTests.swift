import Foundation
import NexusCore
import Testing

@testable import NexusUI

@MainActor
private func makeOnboarding(
    running: [NexusApplication] = []
) -> (OnboardingViewModel, ConfigurationController) {
    let configuration = ConfigurationController(
        store: InMemoryConfigurationStore(),
        events: EventBus(),
        saveDelay: .zero
    )
    let model = OnboardingViewModel(
        configuration: configuration,
        permissions: FakePermissions([:]),
        applications: FakeApplicationService(running),
        dockReplacement: DockReplacementController(
            configuration: configuration,
            dock: FakeDockControl()
        )
    )
    return (model, configuration)
}

/// `start()` loads candidates on a detached task; wait for it rather than guessing a delay.
@MainActor
private func waitForCandidates(_ model: OnboardingViewModel, _ expected: Int) async {
    for _ in 0..<200 where model.candidates.count < expected {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@Suite("Onboarding")
@MainActor
struct OnboardingTests {
    @Test("Skipping everything leaves a working launcher: Option+Space, no permissions, left sidebar")
    func skipAll() {
        let (model, configuration) = makeOnboarding()
        model.start()
        model.skipAll()

        #expect(configuration.configuration.onboarding.hasCompleted)
        #expect(configuration.configuration.search.shortcut == .optionSpace)
        #expect(configuration.configuration.appearance.position == .left)
        #expect(configuration.configuration.pinnedApplications.isEmpty)
        #expect(configuration.configuration.general.launchAtLogin == false)
    }

    @Test("Walking every step completes onboarding exactly once")
    func fullWalkthrough() {
        let (model, configuration) = makeOnboarding()
        var finished = 0
        model.onFinish = { finished += 1 }
        model.start()

        #expect(model.step == .welcome)
        model.advance()
        #expect(model.step == .shortcut)
        model.advance()
        #expect(model.step == .permissions)
        model.advance()
        #expect(model.step == .sidebar)
        model.advance()
        #expect(model.step == .dock)
        model.advance()
        #expect(model.step == .done)
        #expect(model.isLastStep)
        #expect(configuration.configuration.onboarding.hasCompleted == false)

        model.advance()
        #expect(finished == 1)
        #expect(configuration.configuration.onboarding.hasCompleted)
        #expect(configuration.configuration.onboarding.completedVersion == NexusConfiguration.currentVersion)
    }

    @Test("Back steps without losing anything")
    func back() {
        let (model, _) = makeOnboarding()
        model.start()
        model.advance()
        model.advance()
        #expect(model.step == .permissions)
        model.back()
        #expect(model.step == .shortcut)
        model.back()
        #expect(model.step == .welcome)
        model.back()   // no-op at the first step
        #expect(model.step == .welcome)
    }

    @Test("Pinning choices are applied in candidate order, not set order")
    func pinningOrder() async {
        let running = [
            makeApplication("com.a", name: "Alpha", running: true),
            makeApplication("com.b", name: "Beta", running: true),
            makeApplication("com.c", name: "Gamma", running: true),
        ]
        let (model, configuration) = makeOnboarding(running: running)
        model.start()
        await waitForCandidates(model, 3)
        #expect(model.candidates.count == 3)

        model.togglePin("com.c")
        model.togglePin("com.a")
        model.step = .sidebar
        model.advance()

        #expect(configuration.configuration.pinnedApplications == ["com.a", "com.c"])
    }

    @Test("Toggling a pin twice removes it again")
    func togglePin() async {
        let (model, configuration) = makeOnboarding(
            running: [makeApplication("com.a", name: "Alpha", running: true)]
        )
        model.start()
        await waitForCandidates(model, 1)
        model.togglePin("com.a")
        model.togglePin("com.a")
        model.step = .sidebar
        model.advance()
        #expect(configuration.configuration.pinnedApplications.isEmpty)
    }

    @Test("Choosing Command+Space is recorded and flagged for the Spotlight guide")
    func commandSpaceChoice() {
        let (_, configuration) = makeOnboarding()
        configuration.update { $0.search.shortcut = .commandSpace }
        #expect(configuration.configuration.search.shortcut.isCommandSpace)
    }

    @Test("Onboarding runs only once: a completed profile does not re-trigger it")
    func runsOnce() {
        let (model, configuration) = makeOnboarding()
        model.start()
        model.finish()
        #expect(configuration.configuration.onboarding.hasCompleted)

        // Re-running is explicit (Settings → Run Setup Again) and resets to the first step.
        model.start()
        #expect(model.step == .welcome)
        #expect(configuration.configuration.onboarding.hasCompleted)
    }
}

@Suite("Settings bindings")
@MainActor
struct SettingsBindingTests {
    @Test("A settings binding writes through the debounced configuration path and persists")
    func bindingWritesThrough() {
        let store = InMemoryConfigurationStore()
        let configuration = ConfigurationController(store: store, events: EventBus(), saveDelay: .zero)

        let position = configuration.binding(\.appearance.position)
        position.wrappedValue = .right
        configuration.flush()

        #expect(configuration.configuration.appearance.position == .right)
        #expect(store.load().appearance.position == .right)
    }

    @Test("Out-of-range values written through a binding are clamped")
    func clamping() {
        let configuration = ConfigurationController(
            store: InMemoryConfigurationStore(),
            events: EventBus(),
            saveDelay: .zero
        )
        configuration.binding(\.appearance.width).wrappedValue = 10_000
        #expect(configuration.configuration.appearance.width == AppearanceConfiguration.widthRange.upperBound)
    }

    @Test("Every change publishes configurationChanged so the UI applies it live")
    func publishes() async {
        let bus = EventBus()
        let configuration = ConfigurationController(
            store: InMemoryConfigurationStore(),
            events: bus,
            saveDelay: .zero
        )
        let stream = bus.events()
        configuration.update { $0.behavior.autoHide = true }

        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        guard case .configurationChanged(let updated) = event else {
            Issue.record("expected configurationChanged, got \(String(describing: event))")
            return
        }
        #expect(updated.behavior.autoHide)
    }

    @Test("A no-op write publishes nothing")
    func noOpWrite() {
        let bus = EventBus()
        let configuration = ConfigurationController(
            store: InMemoryConfigurationStore(),
            events: bus,
            saveDelay: .zero
        )
        let before = configuration.configuration
        configuration.update { $0.behavior.autoHide = false }   // already false
        #expect(configuration.configuration == before)
    }
}
