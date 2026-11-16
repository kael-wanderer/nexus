import AppKit
import Foundation
import NexusCore
import Testing

@testable import NexusUI

@Suite("Design")
struct DesignTests {
    @Test("Reduce Motion suppresses animation at the call site")
    func reduceMotion() {
        #expect(Design.animation(Design.reveal, reduceMotion: true) == nil)
        #expect(Design.animation(Design.reveal, reduceMotion: false) != nil)
    }

    /// The badge must never hang over the edge of the row it decorates: outside the row is outside
    /// the row's hover region, and that is what made it flash (D110).
    @Test("The remove badge always lands wholly inside the row")
    func removeBadgeStaysInside() {
        let diameter = Design.removeBadgeDiameter
        let cases: [(CGRect, CGSize)] = [
            // A popover tile: a 36 pt icon centred in 76 pt, five points down from the top.
            (CGRect(x: 20, y: 5, width: 36, height: 36), CGSize(width: 76, height: 76)),
            // A row of an expanded vertical bar: the icon at the leading edge.
            (CGRect(x: 4, y: 4, width: 64, height: 64), CGSize(width: 200, height: 72)),
            // A row of a horizontal bar, and a corner case: the icon fills the row exactly.
            (CGRect(x: 4, y: 4, width: 64, height: 64), CGSize(width: 72, height: 72)),
            (CGRect(x: 0, y: 0, width: 12, height: 12), CGSize(width: 12, height: 12)),
        ]
        for (icon, size) in cases {
            let centre = Design.removeBadgeCentre(icon: icon, in: size)
            let badge = CGRect(
                x: centre.x - diameter / 2,
                y: centre.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            #expect(badge.minX >= 0)
            #expect(badge.minY >= 0)
            #expect(badge.maxX <= max(size.width, diameter))
            #expect(badge.maxY <= max(size.height, diameter))
        }

        // Where there is room, it stays on the icon's corner rather than being moved for no reason.
        let roomy = Design.removeBadgeCentre(
            icon: CGRect(x: 30, y: 30, width: 36, height: 36),
            in: CGSize(width: 120, height: 120)
        )
        #expect(roomy == CGPoint(x: 30, y: 30))
    }
}

@Suite("Flyout sizes")
struct FlyoutSizeTests {
    @Test("Every metric grows from small to medium to large")
    func monotonic() {
        let sizes: [FlyoutSize] = [.small, .medium, .large]
        let cardWidths = sizes.map(\.cardSize.width)
        let cardHeights = sizes.map(\.cardSize.height)
        let artworkSizes = sizes.map(\.artworkSize)
        let tileWidths = sizes.map(\.tileSize.width)
        let tileHeights = sizes.map(\.tileSize.height)

        #expect(cardWidths == cardWidths.sorted())
        #expect(cardHeights == cardHeights.sorted())
        #expect(artworkSizes == artworkSizes.sorted())
        #expect(tileWidths == tileWidths.sorted())
        #expect(tileHeights == tileHeights.sorted())
        // Strictly increasing, not just non-decreasing: three sizes that drew the same thing would
        // not be a setting.
        #expect(Set(cardWidths).count == 3)
        #expect(Set(cardHeights).count == 3)
        #expect(Set(artworkSizes).count == 3)
        #expect(Set(tileWidths).count == 3)
        #expect(Set(tileHeights).count == 3)
    }

    @Test("Medium matches the reference screenshot's measurements")
    func mediumIsTheReference() {
        #expect(FlyoutSize.medium.cardSize == CGSize(width: 340, height: 210))
        #expect(FlyoutSize.medium.artworkSize == 190)
        #expect(FlyoutSize.medium.tileSize == CGSize(width: 96, height: 48))
    }
}

@Suite("Shortcuts pane")
struct ShortcutsPaneTests {
    @Test("Two slots holding the same combination is reported")
    func shortcutConflictIsFound() {
        var configuration = NexusConfiguration()
        configuration.search.shortcut = .optionSpace
        configuration.general.focusBarShortcut = .optionSpace

        #expect(ShortcutsPane.conflicts(in: configuration).contains(.optionSpace))
    }

    @Test("Distinct combinations conflict with nothing")
    func noConflictWhenDistinct() {
        var configuration = NexusConfiguration()
        configuration.search.shortcut = .optionSpace
        configuration.general.focusBarShortcut = .focusBarDefault
        configuration.general.windowSwitcherShortcut = .windowSwitcherDefault

        #expect(ShortcutsPane.conflicts(in: configuration).isEmpty)
    }
}

/// A real `PanelController` with real bars, on the last screen — the second display when there is
/// one, so the owner's main display stays free while the tests run.
@MainActor
private func makePanels(
    reduceMotion: Bool,
    autoHide: Bool = false
) async -> (PanelController, SidebarViewModel, ConfigurationController) {
    _ = NSApplication.shared
    let bus = EventBus()
    var initial = NexusConfiguration()
    // Real rows: an empty bar draws a placeholder its layout does not count, and the hosting view
    // then grows the window to fit it.
    initial.setPinnedApplications(["com.a", "com.b"])
    initial.behavior.showRunningApplications = false
    initial.appearance.position = .left
    initial.appearance.width = 64
    if let screen = NSScreen.screens.last, let identity = DisplayService.identity(of: screen) {
        initial.appearance.display = .specific(identity.uuid)
    }
    initial.behavior.hoverExpand = true
    initial.behavior.autoHide = autoHide
    initial.behavior.autoHideDelay = 0.1
    // An expanded bar is longer as well as wider with a search field; the window must follow.
    initial.search.barStyle = .field
    // Rows that follow the real machine's audio device would change the bar's length mid-test.
    initial.general.showVolume = false
    initial.general.showClock = false
    let configuration = ConfigurationController(
        store: InMemoryConfigurationStore(initial),
        events: bus,
        saveDelay: .zero
    )
    let model = SidebarViewModel(
        applications: FakeApplicationService([
            makeApplication("com.a", name: "Alpha"),
            makeApplication("com.b", name: "Beta"),
        ]),
        configuration: configuration,
        events: bus
    )
    let panels = PanelController(
        model: model,
        flyoutModel: WindowFlyoutViewModel(
            service: FakeWindowService(trusted: false),
            previewService: FakePreviewService(),
            permissions: FakePermissions([:]),
            events: bus
        ),
        groupModel: GroupPopoverViewModel(),
        folderModel: FolderStackViewModel(),
        permissions: FakePermissions([:]),
        configuration: configuration,
        events: bus
    )
    panels.reduceMotion = { reduceMotion }
    panels.start()
    await model.refresh()
    return (panels, model, configuration)
}

/// Where a bar's window belongs, by the same rule `PanelController` uses.
@MainActor
private func expectedFrames(
    _ model: SidebarViewModel,
    expanded: Bool,
    hidden: Bool
) -> [CGRect] {
    let appearance = model.appearance
    let size = SidebarLayout.size(zones: model.zones, appearance: appearance, expanded: expanded)
    return DisplayService.screens(for: appearance.display).map {
        SidebarLayout.frame(
            size: size,
            in: $0.visibleFrame,
            position: appearance.position,
            hidden: hidden
        )
    }
}

/// AppKit puts a window on whole points, so a centred bar's half-point origin is rounded.
private func framesMatch(_ actual: [CGRect], _ expected: [CGRect]) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy { a, e in
        abs(a.minX - e.minX) < 1 && abs(a.minY - e.minY) < 1
            && abs(a.width - e.width) < 1 && abs(a.height - e.height) < 1
    }
}

/// The window takes its frame in one step and the bar moves inside it: a transition that touches
/// the expanded state keeps the window wide until the content has finished, and a hide parks the
/// window only once the bar has slid off.
@Suite("Bar window motion")
@MainActor
struct BarWindowMotionTests {
    @Test("Collapse during expand ends at the collapsed frame")
    func collapseDuringExpand() async throws {
        let (panels, model, _) = await makePanels(reduceMotion: false)
        defer { panels.stop() }

        model.setExpanded(true)
        #expect(model.windowIsExpanded)
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: true, hidden: false)))
        model.setExpanded(false)
        // The window stays wide until the content has collapsed inside it.
        #expect(model.windowIsExpanded)

        try await waitUntil { !model.windowIsExpanded }
        #expect(!model.windowIsExpanded)
        #expect(!model.isExpanded)
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: false, hidden: false)))
    }

    @Test("Expand during collapse keeps the window wide")
    func expandDuringCollapse() async throws {
        let (panels, model, _) = await makePanels(reduceMotion: false)
        defer { panels.stop() }

        model.setExpanded(true)
        try await Task.sleep(for: .milliseconds(400))
        model.setExpanded(false)
        model.setExpanded(true)
        // The collapse's completion must not shrink the window under the new expand. Showing an
        // absence needs a fixed wait: longer than the 0.26 s motion.
        try await Task.sleep(for: .milliseconds(400))

        #expect(model.windowIsExpanded)
        #expect(model.isExpanded)
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: true, hidden: false)))
    }

    @Test("Reduce motion shrinks the window at once")
    func reduceMotionShrinksAtOnce() async {
        let (panels, model, _) = await makePanels(reduceMotion: true)
        defer { panels.stop() }

        model.setExpanded(true)
        #expect(model.windowIsExpanded)
        model.setExpanded(false)

        #expect(!model.windowIsExpanded)
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: false, hidden: false)))
    }

    @Test("Reduce motion parks a hidden bar at once")
    func reduceMotionParksAtOnce() async throws {
        let (panels, model, _) = await makePanels(reduceMotion: true, autoHide: true)
        defer { panels.stop() }

        #expect(model.isBarHidden)
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: false, hidden: true)))
        model.hoverChanged(true)
        #expect(!model.isBarHidden)
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: true, hidden: false)))
        model.hoverChanged(false)
        // The hide waits for the auto-hide delay, then collapses and parks with no motion.
        try await waitUntil { model.isBarHidden }
        #expect(model.isBarHidden)
        #expect(!model.windowIsExpanded)
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: false, hidden: true)))
    }

    @Test("Hide parks every bar")
    func hideParksEveryBar() async throws {
        let (panels, model, _) = await makePanels(reduceMotion: false, autoHide: true)
        defer { panels.stop() }

        // Auto-hide starts parked; the pointer arriving reveals the bar on screen at once (and
        // hover-expands it), and the bar slides in inside a window that is already there.
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: false, hidden: true)))
        model.hoverChanged(true)
        #expect(!model.isBarHidden)
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: true, hidden: false)))

        // Leaving collapses and hides at once; both motions end with the window parked narrow.
        model.hoverChanged(false)
        try await waitUntil {
            model.isBarHidden
                && framesMatch(panels.barFrames, expectedFrames(model, expanded: false, hidden: true))
        }
        #expect(model.isBarHidden)
        #expect(!model.windowIsExpanded)
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: false, hidden: true)))
    }
    @Test("Reveal during hide keeps the bar on screen")
    func revealDuringHide() async throws {
        let (panels, model, _) = await makePanels(reduceMotion: false, autoHide: true)
        defer { panels.stop() }

        model.hoverChanged(true)
        model.hoverChanged(false)
        try await waitUntil { model.isBarHidden }
        #expect(model.isBarHidden)
        // The slide off has started; the pointer comes back before it ends.
        model.hoverChanged(true)
        // The hide's completion must not park the window under the revealed bar. Showing an
        // absence needs a fixed wait: longer than the 0.26 s motion.
        try await Task.sleep(for: .milliseconds(400))

        #expect(!model.isBarHidden)
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: true, hidden: false)))
    }
    @Test("A stale collapse's completion never narrows the window under a newer collapse")
    func staleCollapseCompletion() async throws {
        let (panels, model, _) = await makePanels(reduceMotion: false)
        defer { panels.stop() }

        model.setExpanded(true)
        try await Task.sleep(for: .milliseconds(400))
        // Collapse A, then an expand and collapse B before A has finished.
        model.setExpanded(false)
        try await Task.sleep(for: .milliseconds(150))
        model.setExpanded(true)
        model.setExpanded(false)
        // A would have finished by now; B has not. Showing an absence needs a fixed wait.
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.windowIsExpanded)
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: true, hidden: false)))

        try await waitUntil { !model.windowIsExpanded }
        #expect(!model.windowIsExpanded)
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: false, hidden: false)))
    }

    @Test("A stale hide's completion never parks the window under a newer hide")
    func staleHideCompletion() async throws {
        let (panels, model, _) = await makePanels(reduceMotion: false, autoHide: true)
        defer { panels.stop() }

        model.hoverChanged(true)
        model.hoverChanged(false)
        try await waitUntil { model.isBarHidden }
        // Hide A is sliding; reveal and leave again, so hide B starts after the 0.1 s delay.
        model.hoverChanged(true)
        model.hoverChanged(false)
        try await waitUntil { model.isBarHidden }
        // B started just now, after A would have finished; showing an absence needs a fixed wait.
        try await Task.sleep(for: .milliseconds(100))
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: false, hidden: false))
            || framesMatch(panels.barFrames, expectedFrames(model, expanded: true, hidden: false)))

        try await waitUntil {
            framesMatch(panels.barFrames, expectedFrames(model, expanded: false, hidden: true))
        }
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: false, hidden: true)))
    }

    @Test("Toggle Sidebar during a collapse leaves the window narrow when it comes back")
    func suppressDuringCollapse() async throws {
        let (panels, model, _) = await makePanels(reduceMotion: false)
        defer { panels.stop() }

        model.setExpanded(true)
        try await Task.sleep(for: .milliseconds(400))
        model.setExpanded(false)
        panels.toggleSidebar()
        panels.toggleSidebar()

        #expect(!model.windowIsExpanded)
        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: false, hidden: false)))
    }

    @Test("Toggle Sidebar during a hide leaves the window parked when it comes back")
    func suppressDuringHide() async throws {
        let (panels, model, _) = await makePanels(reduceMotion: false, autoHide: true)
        defer { panels.stop() }

        model.hoverChanged(true)
        model.hoverChanged(false)
        try await waitUntil { model.isBarHidden }
        panels.toggleSidebar()
        panels.toggleSidebar()

        #expect(framesMatch(panels.barFrames, expectedFrames(model, expanded: false, hidden: true)))
    }

    @Test("A collapse while the bar is suppressed finishes at once")
    func collapseWhileSuppressed() async throws {
        let (panels, model, _) = await makePanels(reduceMotion: false)
        defer { panels.stop() }

        model.setExpanded(true)
        panels.toggleSidebar()
        model.setExpanded(false)

        #expect(!model.windowIsExpanded)
        #expect(!model.isExpanded)
    }
}
