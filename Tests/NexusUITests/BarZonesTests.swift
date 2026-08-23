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
            fixedRows: [1] + Array(repeating: 1, count: 2),
            pinnedRows: 4,
            runningRows: 3,
            appearance: appearance,
            available: 2_000
        )
        #expect(zones.pinnedRows == 4)
        #expect(zones.runningRows == 3)
        #expect(zones.pinnedExtent == extent(4))
    }

    @Test("A ceiling, when one is set, binds before the screen does")
    func capped() {
        var appearance = appearance
        appearance.pinnedLimit = 10
        appearance.runningLimit = 5

        let zones = SidebarLayout.zones(
            fixedRows: [1] + Array(repeating: 1, count: 2),
            pinnedRows: 14,
            runningRows: 30,
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
            fixedRows: [1] + Array(repeating: 1, count: 2),
            pinnedRows: 14,
            runningRows: 30,
            appearance: appearance,
            available: available
        )
        // Head, Trash, Search, pinned, running: five sections, so four separators.
        let fixed = SidebarLayout.outerPadding * 2 + extent(1) * 3
            + 4 * (Design.separatorHeight + SidebarLayout.separatorSpacing * 2)
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
            fixedRows: [1] + Array(repeating: 1, count: 2),
            pinnedRows: 10,
            runningRows: 10,
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
            fixedRows: Array(repeating: 1, count: 2),
            pinnedRows: 40,
            runningRows: 9,
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
            fixedRows: Array(repeating: 1, count: 2), pinnedRows: 40, runningRows: 4,
            appearance: appearance, available: 600
        )
        let withoutRunning = SidebarLayout.zones(
            fixedRows: Array(repeating: 1, count: 2), pinnedRows: 40, runningRows: 0,
            appearance: appearance, available: 600
        )
        #expect(withoutRunning.runningRows == 0)
        #expect(withoutRunning.pinnedRows > withRunning.pinnedRows)
    }

    /// The complaint this replaced the fixed limits with: half the screen empty and the running
    /// section still scrolling.
    @Test("With no ceiling set the bar grows into the screen it has, then scrolls")
    func growsToFitTheScreen() {
        let short = SidebarLayout.zones(
            fixedRows: [1] + Array(repeating: 1, count: 2), pinnedRows: 0, runningRows: 30,
            appearance: appearance, available: 600
        )
        let tall = SidebarLayout.zones(
            fixedRows: [1] + Array(repeating: 1, count: 2), pinnedRows: 0, runningRows: 30,
            appearance: appearance, available: 1_400
        )
        // A taller edge shows more, and neither shows more than it holds.
        #expect(tall.runningRows > short.runningRows)
        #expect(short.runningRows == short.slots)
        #expect(tall.runningRows == tall.slots)
        #expect(short.total <= 600)
        #expect(tall.total <= 1_400)

        // Enough screen for everything: nothing scrolls, and the bar is no taller than it needs.
        let huge = SidebarLayout.zones(
            fixedRows: [1] + Array(repeating: 1, count: 2), pinnedRows: 0, runningRows: 30,
            appearance: appearance, available: 4_000
        )
        #expect(huge.runningRows == 30)
        #expect(huge.total < 4_000)
    }

    /// A left or right bar measures the screen's height; a top or bottom one measures its width.
    /// On a 1920 × 1080 display that is a different number of icons, and the caller is what knows
    /// which — the zones only ever see "available".
    @Test("The same screen holds different numbers of rows on a side edge and on a main edge")
    func edgeAxisChangesCapacity() {
        let side = SidebarLayout.zones(
            fixedRows: [1] + Array(repeating: 1, count: 2), pinnedRows: 0, runningRows: 40,
            appearance: appearance, available: 1_080 - 25 - 16      // height, less menu bar
        )
        let main = SidebarLayout.zones(
            fixedRows: [1] + Array(repeating: 1, count: 2), pinnedRows: 0, runningRows: 40,
            appearance: appearance, available: 1_920 - 16           // width
        )
        #expect(main.slots > side.slots)
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
            fixedRows: [1] + Array(repeating: 1, count: 2), pinnedRows: 3, runningRows: 3,
            appearance: appearance, available: 1_000
        )
        let vertical = SidebarLayout.size(zones: zones, appearance: appearance, expanded: false)
        #expect(vertical.width == CGFloat(appearance.width))
        #expect(vertical.height == zones.total)

        appearance.position = .bottom
        let horizontal = SidebarLayout.size(zones: zones, appearance: appearance, expanded: false)
        #expect(horizontal.height == SidebarLayout.width(appearance, expanded: false))
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
        // The bar grows into the screen it has and scrolls the remainder, rather than stopping at
        // a number: three pins plus as many running rows as 900 pt holds.
        #expect(zones.pinnedRows == 3)
        #expect(zones.runningRows == zones.slots - 3)
        #expect(zones.runningRows > SidebarLayout.runningFloor)
        #expect(zones.total <= 900)
        // Six parts, each its own section so each gets a separator: no launcher and nothing
        // playing here, so pinned, running, Trash, Search.
        #expect(model.sectionRowCounts == [zones.pinnedRows, zones.runningRows, 1, 1])
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

@MainActor
@Suite("Now playing row")
struct NowPlayingRowTests {
    private func makeModel(showNowPlaying: Bool) -> SidebarViewModel {
        var initial = NexusConfiguration()
        initial.general.showNowPlaying = showNowPlaying
        let configuration = ConfigurationController(
            store: InMemoryConfigurationStore(initial),
            events: EventBus(),
            saveDelay: .zero
        )
        let model = SidebarViewModel(
            applications: FakeApplicationService([]),
            configuration: configuration,
            events: EventBus()
        )
        model.availableExtent = 1_000
        model.openSearch = {}
        model.mediaCommand = { _ in }
        return model
    }

    private var track: NowPlaying {
        NowPlaying(title: "Tunnel Vision", artist: "Aurora B.Polaris", playerBundleIdentifier: "com.spotify.client", isPlaying: true)
    }

    @Test("Nothing playing means no row, not an empty one")
    func absentWhenIdle() {
        let model = makeModel(showNowPlaying: true)
        #expect(model.showsNowPlayingRow == false)
        #expect(model.tailRowCount == 2)

        model.nowPlayingChanged(track, isActive: true)
        #expect(model.showsNowPlayingRow)
        // Artwork and controls: the player is two rows, not one (M16).
        #expect(model.tailRowCount == 4)
    }

    @Test("With the setting off the row never appears, and its slot goes to the applications")
    func settingGates() {
        let model = makeModel(showNowPlaying: false)
        model.nowPlayingChanged(track, isActive: true)

        #expect(model.showsNowPlayingRow == false)
        #expect(model.tailRowCount == 2)
    }

    /// Audio playing with no cooperating player: controls, and no invented title.
    @Test("A player that publishes nothing still gets a row with controls")
    func controlsWithoutMetadata() {
        let model = makeModel(showNowPlaying: true)
        model.nowPlayingChanged(NowPlaying(), isActive: true)

        #expect(model.showsNowPlayingRow)
        #expect(model.nowPlaying.hasMetadata == false)
    }

    @Test("The row asks the panel to reframe only when it appears or disappears")
    func reframesOnAppearance() {
        let model = makeModel(showNowPlaying: true)
        var layouts = 0
        model.layoutDidChange = { layouts += 1 }

        model.nowPlayingChanged(track, isActive: true)
        #expect(layouts == 1)

        // A different track is the same row: no reframe.
        model.nowPlayingChanged(
            NowPlaying(title: "Weightless", playerBundleIdentifier: "com.spotify.client", isPlaying: true),
            isActive: true
        )
        #expect(layouts == 1)

        model.nowPlayingChanged(NowPlaying(), isActive: false)
        #expect(layouts == 2)
    }

    @Test("Transport commands go through the injected command, not straight to the system")
    func commandsAreInjected() {
        let model = makeModel(showNowPlaying: true)
        var sent: [MediaKey] = []
        model.mediaCommand = { sent.append($0) }

        model.togglePlayback()
        model.nextTrack()
        model.previousTrack()
        #expect(sent == [.play, .next, .previous])
    }
}

@MainActor
@Suite("Media player width")
struct MediaPlayerWidthTests {
    private func makeModel(
        position: SidebarPosition,
        width: MediaWidth,
        expanded: Bool = false
    ) -> SidebarViewModel {
        var initial = NexusConfiguration()
        initial.general.showNowPlaying = true
        initial.appearance.position = position
        initial.appearance.mediaWidth = width
        let configuration = ConfigurationController(
            store: InMemoryConfigurationStore(initial),
            events: EventBus(),
            saveDelay: .zero
        )
        let model = SidebarViewModel(
            applications: FakeApplicationService([]),
            configuration: configuration,
            events: EventBus()
        )
        model.availableExtent = 2_000
        model.openSearch = {}
        model.mediaCommand = { _ in }
        if expanded { model.setExpanded(true) }
        model.nowPlayingChanged(
            NowPlaying(title: "Loki S01", playerBundleIdentifier: "org.videolan.vlc", isPlaying: true),
            isActive: true,
            players: ["org.videolan.vlc"],
            position: MediaPosition(position: 60, duration: 240)
        )
        return model
    }

    @Test("A horizontal bar gets the wide player, four slots of it")
    func wideOnHorizontal() {
        let model = makeModel(position: .bottom, width: .wide)
        #expect(model.isMediaPlayerWide)
        #expect(model.nowPlayingRowCount == 4)
        #expect(model.sectionRowCounts.contains(4))
    }

    /// Four rows of *height* on a 64 pt bar buy nothing a horizontal scrubber can use.
    @Test("A narrow vertical bar stays compact whatever the setting says")
    func compactOnVertical() {
        let model = makeModel(position: .left, width: .wide)
        #expect(model.isMediaPlayerWide == false)
        #expect(model.nowPlayingRowCount == 2)
    }

    @Test("Hover-expanding a vertical bar makes room for the wide player")
    func wideWhenExpanded() {
        let model = makeModel(position: .left, width: .wide, expanded: true)
        #expect(model.isExpanded)
        #expect(model.isMediaPlayerWide)
    }

    @Test("Compact is compact everywhere")
    func compactSetting() {
        #expect(makeModel(position: .bottom, width: .compact).isMediaPlayerWide == false)
        #expect(makeModel(position: .bottom, width: .compact).nowPlayingRowCount == 2)
    }

    @Test("The player's slots come out of the applications, and the tail still fits")
    func costsSlots() {
        let wide = makeModel(position: .bottom, width: .wide)
        let compact = makeModel(position: .bottom, width: .compact)
        #expect(wide.zones.total > compact.zones.total)
        #expect(wide.zones.total <= 2_000)
    }
}
