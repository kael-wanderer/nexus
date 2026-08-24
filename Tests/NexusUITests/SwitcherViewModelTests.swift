import CoreGraphics
import Foundation
import NexusCore
import Testing

@testable import NexusUI

@Suite("Switcher view model")
@MainActor
struct SwitcherViewModelTests {
    func window(_ bundle: String, _ name: String, _ title: String, number: CGWindowID) -> NexusWindow {
        NexusWindow(
            identity: WindowIdentity(owner: ApplicationIdentity(bundleIdentifier: bundle), number: number),
            title: title,
            applicationName: name
        )
    }

    func model(
        _ windows: [NexusWindow],
        permissions: [Permission: PermissionStatus] = [.accessibility: .granted]
    ) async -> SwitcherViewModel {
        let service = FakeWindowService()
        for window in windows {
            await service.setWindows(
                windows.filter { $0.identity.owner == window.identity.owner },
                for: window.identity.owner.bundleIdentifier
            )
        }
        let model = SwitcherViewModel(
            service: service,
            previewService: FakePreviewService(),
            permissions: FakePermissions(permissions),
            events: EventBus(),
            configuration: ConfigurationController(store: InMemoryConfigurationStore(), events: EventBus(), saveDelay: .zero)
        )
        await model.reload()
        return model
    }

    @Test("Every window is a card, one per window and not one per application")
    func cardPerWindow() async {
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Google", number: 1),
            window("com.apple.Safari", "Safari", "Nexus", number: 2),
            window("com.apple.finder", "Finder", "Macintosh HD", number: 3),
        ])
        #expect(model.sections.count == 1)
        #expect(model.sections[0].windows.count == 3)
    }

    @Test("The filter matches an application name and a window title")
    func filter() async {
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Google", number: 1),
            window("com.apple.finder", "Finder", "Downloads", number: 2),
        ])

        model.query = "saf"
        #expect(model.sections.flatMap(\.windows).map(\.title) == ["Google"])

        model.query = "down"
        #expect(model.sections.flatMap(\.windows).map(\.title) == ["Downloads"])

        model.query = "zzz"
        #expect(model.sections.flatMap(\.windows).isEmpty)

        model.query = ""
        #expect(model.sections.flatMap(\.windows).count == 2)
    }

    @Test("Sorting by title, and reversed is the exact inverse")
    func sortByTitle() async {
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Beta", number: 1),
            window("com.apple.finder", "Finder", "Alpha", number: 2),
        ])
        model.sort = .title
        #expect(model.sections.flatMap(\.windows).map(\.title) == ["Alpha", "Beta"])

        model.isReversed = true
        #expect(model.sections.flatMap(\.windows).map(\.title) == ["Beta", "Alpha"])
    }

    @Test("Recency follows activation, most recent first")
    func sortByRecency() async {
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Google", number: 1),
            window("com.apple.finder", "Finder", "Downloads", number: 2),
        ])
        model.sort = .recent
        model.noteActivation(ApplicationIdentity(bundleIdentifier: "com.apple.finder"))
        #expect(model.sections.flatMap(\.windows).map(\.applicationName) == ["Finder", "Safari"])

        model.noteActivation(ApplicationIdentity(bundleIdentifier: "com.apple.Safari"))
        #expect(model.sections.flatMap(\.windows).map(\.applicationName) == ["Safari", "Finder"])
    }

    @Test("Grouping by application makes one section per application, named for it")
    func groupByApplication() async {
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Google", number: 1),
            window("com.apple.Safari", "Safari", "Nexus", number: 2),
            window("com.apple.finder", "Finder", "Downloads", number: 3),
        ])
        model.sort = .application
        model.grouping = .application
        #expect(model.sections.map(\.title) == ["Finder", "Safari"])
        #expect(model.sections.map { $0.windows.count } == [1, 2])
    }

    @Test("Add Stack reduces a window selection to distinct applications")
    func addStack() async {
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Google", number: 1),
            window("com.apple.Safari", "Safari", "Nexus", number: 2),
            window("com.apple.finder", "Finder", "Downloads", number: 3),
        ])
        model.toggleSelection("com.apple.Safari#1")
        model.toggleSelection("com.apple.Safari#2")
        model.toggleSelection("com.apple.finder#3")

        #expect(model.canAddStack)
        let group = model.stackFromSelection()
        #expect(group?.applications.sorted() == ["com.apple.Safari", "com.apple.finder"])
    }

    @Test("Add Stack is unavailable with nothing selected")
    func addStackNeedsSelection() async {
        let model = await self.model([window("com.apple.Safari", "Safari", "Google", number: 1)])
        #expect(model.canAddStack == false)
        #expect(model.stackFromSelection() == nil)
    }

    @Test("Escape clears a filter before it closes the panel")
    func escapeIsTwoSteps() async {
        let model = await self.model([window("com.apple.Safari", "Safari", "Google", number: 1)])
        var closed = false
        model.onClose = { closed = true }

        model.query = "saf"
        model.clearQueryOrClose()
        #expect(model.query.isEmpty)
        #expect(closed == false)

        model.clearQueryOrClose()
        #expect(closed)
    }

    @Test("Arrows move the focus and wrap at the ends of a row")
    func focusMoves() async {
        let model = await self.model([
            window("a.one", "One", "1", number: 1),
            window("b.two", "Two", "2", number: 2),
            window("c.three", "Three", "3", number: 3),
            window("d.four", "Four", "4", number: 4),
        ])
        // `.recent` with nothing activated yet ties every window, so the tiebreak falls back to
        // the bundle identifier alphabetically — deterministic regardless of what order the fake
        // service's dictionary happens to enumerate applications in.
        model.sort = .recent
        model.focusFirst()
        #expect(model.focused == "a.one#1")

        model.moveFocus(.right, columns: 2)
        #expect(model.focused == "b.two#2")

        // Wraps to the start of the same row rather than falling into the next one.
        model.moveFocus(.right, columns: 2)
        #expect(model.focused == "a.one#1")

        model.moveFocus(.down, columns: 2)
        #expect(model.focused == "c.three#3")
    }

    @Test("Closing a card asks the service and does not remove it")
    func closeAsksTheService() async {
        let service = FakeWindowService()
        let target = window("com.apple.Safari", "Safari", "Google", number: 1)
        await service.setWindows([target], for: "com.apple.Safari")
        let model = SwitcherViewModel(
            service: service,
            previewService: FakePreviewService(),
            permissions: FakePermissions([.accessibility: .granted]),
            events: EventBus(),
            configuration: ConfigurationController(store: InMemoryConfigurationStore(), events: EventBus(), saveDelay: .zero)
        )
        await model.reload()

        await model.close(target)
        #expect(await service.closed == [target.identity])
        #expect(model.sections.flatMap(\.windows).count == 1)
    }

    @Test("Accessibility denied shows the gate and no cards")
    func accessibilityGate() async {
        let model = SwitcherViewModel(
            service: FakeWindowService(),
            previewService: FakePreviewService(),
            permissions: FakePermissions([:]),
            events: EventBus(),
            configuration: ConfigurationController(store: InMemoryConfigurationStore(), events: EventBus(), saveDelay: .zero)
        )
        await model.reload()
        #expect(model.showsAccessibilityGate)
        #expect(model.sections.isEmpty)
    }

    @Test("Screen Recording denied offers it once, and never again once dismissed")
    func previewsOffer() async {
        let model = await self.model([window("com.apple.Safari", "Safari", "Google", number: 1)])
        #expect(model.showsPreviewsOffer)
        model.dismissPreviewsOffer()
        #expect(model.showsPreviewsOffer == false)
    }
}
