import CoreGraphics
import Foundation
import NexusCore
import Testing

@testable import NexusUI

@Suite("Bar zones")
struct BarZonesTests {
    private var appearance: AppearanceConfiguration {
        var appearance = AppearanceConfiguration()
        appearance.iconSize = 40      // rows are 48 pt, gaps 8 pt
        appearance.iconSpacing = 8
        return appearance
    }

    /// One row 48, one gap 8: `n` rows are `56n - 8`.
    private func extent(_ rows: Int) -> CGFloat {
        rows == 0 ? 0 : CGFloat(rows) * 56 - 8
    }

    @Test("With room to spare each section shows what it has, up to its limit")
    func withinLimits() {
        let zones = SidebarLayout.zones(
            headRows: 1,
            pinnedRows: 4,
            runningRows: 3,
            tailRows: 2,
            appearance: appearance,
            available: 2_000
        )
        #expect(zones.pinnedRows == 4)
        #expect(zones.runningRows == 3)
        #expect(zones.pinnedExtent == extent(4))
    }

    @Test("A section past its limit is capped and scrolls inside itself")
    func capped() {
        var appearance = appearance
        appearance.pinnedLimit = 10
        appearance.runningLimit = 5

        let zones = SidebarLayout.zones(
            headRows: 1,
            pinnedRows: 14,
            runningRows: 30,
            tailRows: 2,
            appearance: appearance,
            available: 2_000
        )
        #expect(zones.pinnedRows == 10)
        #expect(zones.runningRows == 5)
    }

    /// The bug this milestone exists for: thirty applications used to push Trash and Search past
    /// the bottom of the panel.
    @Test("The tail always fits, whatever the middle holds")
    func tailAlwaysFits() {
        let available: CGFloat = 800
        let zones = SidebarLayout.zones(
            headRows: 1,
            pinnedRows: 14,
            runningRows: 30,
            tailRows: 2,
            appearance: appearance,
            available: available
        )
        let fixed = SidebarLayout.outerPadding * 2 + extent(1) + extent(2)
            + 3 * (Design.separatorHeight + SidebarLayout.separatorSpacing * 2)
        #expect(zones.total <= available)
        #expect(zones.total == fixed + zones.pinnedExtent + zones.runningExtent)
        #expect(zones.pinnedExtent + zones.runningExtent <= available - fixed)
    }

    @Test("A screen too small for both limits shrinks the middle, not the tail")
    func shrinksMiddle() {
        var appearance = appearance
        appearance.pinnedLimit = 10
        appearance.runningLimit = 5

        // Room for the head, the tail, separators and about four middle rows.
        let zones = SidebarLayout.zones(
            headRows: 1,
            pinnedRows: 10,
            runningRows: 10,
            tailRows: 2,
            appearance: appearance,
            available: 460
        )
        #expect(zones.pinnedRows + zones.runningRows < 15)
        #expect(zones.pinnedRows >= 1)
        #expect(zones.total <= 460)
    }

    @Test("Running keeps its floor even when the pinned section wants everything")
    func runningFloor() {
        var appearance = appearance
        appearance.pinnedLimit = 40
        appearance.runningLimit = 5

        let zones = SidebarLayout.zones(
            headRows: 0,
            pinnedRows: 40,
            runningRows: 9,
            tailRows: 2,
            appearance: appearance,
            available: 600
        )
        #expect(zones.runningRows == SidebarLayout.runningFloor)
        #expect(zones.pinnedRows > 0)
    }

    @Test("Nothing running means no floor to reserve, and the pins get the room")
    func noRunning() {
        var appearance = appearance
        appearance.pinnedLimit = 40

        let withRunning = SidebarLayout.zones(
            headRows: 0, pinnedRows: 40, runningRows: 4, tailRows: 2,
            appearance: appearance, available: 600
        )
        let withoutRunning = SidebarLayout.zones(
            headRows: 0, pinnedRows: 40, runningRows: 0, tailRows: 2,
            appearance: appearance, available: 600
        )
        #expect(withoutRunning.runningRows == 0)
        #expect(withoutRunning.pinnedRows > withRunning.pinnedRows)
    }

    @Test("Whole rows only: half a row reads as a clipped icon, not as something to scroll")
    func wholeRows() {
        #expect(SidebarLayout.rows(fitting: extent(3) + 20, appearance: appearance) == 3)
        #expect(SidebarLayout.rows(fitting: extent(3), appearance: appearance) == 3)
        #expect(SidebarLayout.rows(fitting: 20, appearance: appearance) == 0)
    }

    @Test("The panel is as wide as ever; only the extent along the bar changes")
    func size() {
        var appearance = appearance
        appearance.position = .left
        let zones = SidebarLayout.zones(
            headRows: 1, pinnedRows: 3, runningRows: 3, tailRows: 2,
            appearance: appearance, available: 1_000
        )
        let vertical = SidebarLayout.size(zones: zones, appearance: appearance, expanded: false)
        #expect(vertical.width == CGFloat(appearance.width))
        #expect(vertical.height == zones.total)

        appearance.position = .bottom
        let horizontal = SidebarLayout.size(zones: zones, appearance: appearance, expanded: false)
        #expect(horizontal.height == CGFloat(appearance.width))
        #expect(horizontal.width == zones.total)
    }
}

@MainActor
@Suite("Bar zones in the sidebar")
struct SidebarZoneTests {
    private func makeModel(
        pinned: [String],
        running: Int,
        available: CGFloat
    ) -> SidebarViewModel {
        let applications = (0..<running).map {
            makeApplication("run.\($0)", name: "R\($0)", running: true)
        }
        let pins = pinned.map { makeApplication($0, name: $0) }
        var initial = NexusConfiguration()
        initial.setPinnedApplications(pinned)
        let configuration = ConfigurationController(
            store: InMemoryConfigurationStore(initial),
            events: EventBus(),
            saveDelay: .zero
        )
        let model = SidebarViewModel(
            applications: FakeApplicationService(applications + pins),
            configuration: configuration,
            events: EventBus()
        )
        model.availableExtent = available
        model.openSearch = {}
        return model
    }

    @Test("Thirty running applications leave the tail rows inside the bar")
    func thirtyApplications() async {
        let model = makeModel(pinned: ["a", "b", "c"], running: 30, available: 900)
        await model.refresh()

        let zones = model.zones
        #expect(model.running.count == 30)
        #expect(zones.runningRows <= 5)
        #expect(zones.total <= 900)
        // Tail rows counted, and counted last.
        #expect(model.sectionRowCounts.last == 2)
        #expect(model.sectionRowCounts == [zones.pinnedRows, zones.runningRows, 2])
    }

    @Test("A group counts as one row against the pinned limit")
    func groupsCountOnce() async {
        let applications = (0..<12).map { makeApplication("app.\($0)", name: "A\($0)") }
        var initial = NexusConfiguration()
        initial.appearance.pinnedLimit = 3
        initial.pinnedEntries = [
            .group(ApplicationGroup(name: "Group", applications: (0..<9).map { "app.\($0)" })),
            .application("app.9"),
            .application("app.10"),
            .application("app.11"),
        ]
        let configuration = ConfigurationController(
            store: InMemoryConfigurationStore(initial),
            events: EventBus(),
            saveDelay: .zero
        )
        let model = SidebarViewModel(
            applications: FakeApplicationService(applications),
            configuration: configuration,
            events: EventBus()
        )
        model.availableExtent = 2_000
        await model.refresh()

        // Four rows exist, three fit the limit — nine applications hide inside one of them.
        #expect(model.pinned.count == 4)
        #expect(model.zones.pinnedRows == 3)
        #expect(model.pinnedItems.count == 12)
    }
}
