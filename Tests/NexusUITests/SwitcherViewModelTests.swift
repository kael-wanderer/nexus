import CoreGraphics
import Foundation
import NexusCore
import Testing

@testable import NexusUI

@Suite("Switcher view model")
@MainActor
struct SwitcherViewModelTests {
    func window(
        _ bundle: String,
        _ name: String,
        _ title: String,
        number: CGWindowID,
        frame: CGRect = .zero
    ) -> NexusWindow {
        NexusWindow(
            identity: WindowIdentity(owner: ApplicationIdentity(bundleIdentifier: bundle), number: number),
            title: title,
            frame: frame,
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

    @Test("Recency orders applications, but never reorders windows within one of them")
    func recentKeepsAXOrderWithinAnApplication() async {
        // Deliberately not in number order: a sort keyed off `identity.number` or `title` would
        // pass here by accident. This is the AX order the fake service was handed, and `.recent`
        // must leave it alone regardless of which applications have been activated.
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Docs", number: 2),
            window("com.apple.Safari", "Safari", "Google", number: 1),
            window("com.apple.finder", "Finder", "Downloads", number: 3),
        ])
        model.sort = .recent

        // Neither application has been activated: both rank equal, so applications tie-break
        // alphabetically by bundle identifier ("com.apple.Safari" before "com.apple.finder") —
        // but the two Safari windows must still come back Docs-then-Google, their AX order.
        #expect(model.sections.flatMap(\.windows).map(\.title) == ["Docs", "Google", "Downloads"])

        // Activating Finder moves it to the front. Safari's two windows, still un-activated,
        // keep their relative order behind it.
        model.noteActivation(ApplicationIdentity(bundleIdentifier: "com.apple.finder"))
        #expect(model.sections.flatMap(\.windows).map(\.title) == ["Downloads", "Docs", "Google"])
    }

    @Test("Grouping by display groups by the injected display name, deciding a straddling window by its origin")
    func groupByDisplay() async {
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Google", number: 1, frame: CGRect(x: 100, y: 0, width: 200, height: 200)),
            window("com.apple.finder", "Finder", "Downloads", number: 2, frame: CGRect(x: 1100, y: 0, width: 200, height: 200)),
            // Spans the boundary at x = 1000 (900...1200): design §4 says it belongs to whichever
            // display holds its origin, which here is the left one.
            window("com.apple.Chrome", "Chrome", "Straddler", number: 3, frame: CGRect(x: 900, y: 0, width: 300, height: 200)),
        ])
        var asked: [CGRect] = []
        model.displayName = { frame in
            asked.append(frame)
            return frame.origin.x < 1000 ? "Left" : "Right"
        }
        model.grouping = .display

        let byTitle = Dictionary(uniqueKeysWithValues: model.sections.map { ($0.title, Set($0.windows.map(\.title))) })
        #expect(byTitle["Left"] == ["Google", "Straddler"])
        #expect(byTitle["Right"] == ["Downloads"])
        // The hook was asked with the straddling window's whole frame — its origin is what the
        // hook (and, in production, `NSScreen` lookup) uses to decide, not its far edge.
        #expect(asked.contains(CGRect(x: 900, y: 0, width: 300, height: 200)))
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

    @Test("Tab advances one card at a time when flat, wrapping at the end")
    func focusNextFlat() async {
        let model = await self.model([
            window("a.one", "One", "1", number: 1),
            window("b.two", "Two", "2", number: 2),
            window("c.three", "Three", "3", number: 3),
        ])
        model.sort = .recent
        model.focusFirst()
        #expect(model.focused == "a.one#1")

        model.focusNext()
        #expect(model.focused == "b.two#2")

        model.focusNext()
        #expect(model.focused == "c.three#3")

        model.focusNext()
        #expect(model.focused == "a.one#1")
    }

    @Test("Tab jumps to the first card of the next section when grouped, wrapping at the end")
    func focusNextGrouped() async {
        let model = await self.model([
            window("app.a", "Alpha", "1", number: 1),
            window("app.b", "Bravo", "2", number: 2),
            window("app.c", "Charlie", "3", number: 3),
        ])
        model.sort = .application
        model.grouping = .application
        model.focusFirst()
        #expect(model.focused == "app.a#1")

        model.focusNext()
        #expect(model.focused == "app.b#2")

        model.focusNext()
        #expect(model.focused == "app.c#3")

        model.focusNext()
        #expect(model.focused == "app.a#1")
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

    @Test("An application URL resolves to the same value on repeated lookups, and a bogus bundle identifier resolves to nil both times")
    func applicationURLIsMemoized() async {
        let model = await self.model([])
        // Finder is present on every machine this test runs on; two lookups must agree, which is
        // what the cache promises (`SwitcherCard` reads this twice per body evaluation and must
        // never see it flip between calls).
        let first = model.applicationURL(forBundleIdentifier: "com.apple.finder")
        let second = model.applicationURL(forBundleIdentifier: "com.apple.finder")
        #expect(first != nil)
        #expect(first == second)

        // A bundle identifier LaunchServices can't resolve stays nil on every call, rather than
        // caching a bad answer.
        #expect(model.applicationURL(forBundleIdentifier: "not.a.real.bundle.id") == nil)
        #expect(model.applicationURL(forBundleIdentifier: "not.a.real.bundle.id") == nil)
    }
}
