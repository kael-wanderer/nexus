import AppKit
import NexusCore
import SwiftUI

public struct SidebarItem: Identifiable, Equatable, Sendable {
    public let identity: ApplicationIdentity
    public let name: String
    public let bundleURL: URL
    public var isRunning: Bool
    public var isActive: Bool
    public var windowCount: Int
    public var isPinned: Bool

    public var id: String { identity.bundleIdentifier }

    public init(application: NexusApplication, isPinned: Bool) {
        identity = application.identity
        name = application.name
        bundleURL = application.bundleURL
        isRunning = application.isRunning
        isActive = application.isActive
        windowCount = application.windowCount
        self.isPinned = isPinned
    }
}

/// One drawn row of the pinned section: an application, a group of them (M13), or a folder (M21).
public enum SidebarRow: Identifiable, Equatable, Sendable {
    case application(SidebarItem)
    case group(SidebarGroup)
    case folder(SidebarFolder)

    public var id: String {
        switch self {
        case .application(let item): item.id
        case .group(let group): group.id
        case .folder(let folder): folder.id
        }
    }

    public var item: SidebarItem? {
        guard case .application(let item) = self else { return nil }
        return item
    }

    public var group: SidebarGroup? {
        guard case .group(let group) = self else { return nil }
        return group
    }

    public var folder: SidebarFolder? {
        guard case .folder(let folder) = self else { return nil }
        return folder
    }
}

/// One minimized window, ready to draw (M22). The icon comes from the owning application, which
/// is the only picture there is without Screen Recording.
public struct MinimizedWindow: Identifiable, Equatable, Sendable {
    public let identity: WindowIdentity
    public let title: String
    public let applicationName: String
    public let bundleURL: URL?

    public var id: String { "\(identity.owner.bundleIdentifier)#\(identity.number)" }

    /// What the row says when the window has no title of its own.
    public var name: String { title.isEmpty ? applicationName : title }
}

/// A pinned folder, ready to draw. Its contents are not here: they are read when the stack opens
/// (M21), so the bar never waits on a disk.
public struct SidebarFolder: Identifiable, Equatable, Sendable {
    public let path: String
    public let name: String

    public var id: String { DockEntry.folder(path).id }
    public var url: URL { URL(fileURLWithPath: path) }
}

/// A group with its members resolved, ready to draw.
public struct SidebarGroup: Identifiable, Equatable, Sendable {
    public let group: ApplicationGroup
    public var items: [SidebarItem]

    public var id: String { DockEntry.group(group).id }
    public var name: String { group.name }
    /// One dot for the whole group: any member running lights it. No window-count badge — a
    /// number summing several applications answers a question nobody asked.
    public var isRunning: Bool { items.contains(where: \.isRunning) }
    public var isActive: Bool { items.contains(where: \.isActive) }
}

/// Views own no system logic (§62): the view binds to this, this talks to service protocols.
@MainActor
@Observable
public final class SidebarViewModel {
    public private(set) var pinned: [SidebarRow] = []
    public private(set) var running: [SidebarItem] = []

    /// Applications only, in dock order — what the flyout anchor and the window features work
    /// with. A group's members are included.
    public var pinnedItems: [SidebarItem] {
        pinned.flatMap { row in row.group?.items ?? row.item.map { [$0] } ?? [] }
    }

    /// Read straight through to the single source of truth. `ConfigurationController` is
    /// `@Observable`, so SwiftUI still re-renders when these change.
    public var appearance: AppearanceConfiguration { configuration.configuration.appearance }
    public var behavior: BehaviorConfiguration { configuration.configuration.behavior }
    public var general: GeneralConfiguration { configuration.configuration.general }
    public var search: SearchConfiguration { configuration.configuration.search }

    /// Hover-expanded (names visible). Never true when `behavior.hoverExpand` is off.
    public var isExpanded = false

    /// What is playing, for the tail's now-playing row (M15). Empty until the service says
    /// otherwise, and the row is absent while it is.
    public private(set) var nowPlaying = NowPlaying()
    public private(set) var nowPlayingIsActive = false
    /// The application making the sound when no player published a track — a browser, say. It gives
    /// the row an icon instead of a blank square (D75).
    public private(set) var nowPlayingFallbackPlayer: String?
    /// Where the player is, when it will say (M16). Drives the progress line under the row's
    /// artwork and the popover's scrubber.
    public private(set) var nowPlayingPosition: MediaPosition?

    /// Windows that have been minimized, newest first (M22). Order is kept here because the window
    /// layer has none to give: `AXMinimized` is a boolean, and enumeration order is whatever the
    /// application's window list happens to be.
    public private(set) var minimized: [MinimizedWindow] = []

    /// Rows the minimized section may take. The tail is subtracted from the applications before
    /// they are laid out, so an unbounded tail is a bar that shrinks every time somebody minimises
    /// something. Older windows stay reachable in their application's flyout.
    public static let minimizedLimit = 3

    /// The row the keyboard is on, or `nil` when the bar is not in keyboard mode (M23). Every row
    /// that can be clicked can be focused, in the order they are drawn.
    public private(set) var focusedRowID: String?

    /// Asks the panel to take, or give back, the keyboard. Set by `PanelController`.
    @ObservationIgnored public var setKeyboardFocus: ((Bool) -> Void)?

    /// Drives which Trash icon the utility row draws.
    public private(set) var trashIsEmpty = TrashService.isEmpty

    /// The row currently being dragged, so it can be drawn as a gap (D59).
    public private(set) var draggingIdentifier: String?
    /// The row the drag is over the *middle* of, which is what means "put these together" rather
    /// than "move me here" — highlighted while it holds, and what a drop acts on (M13, D103).
    public private(set) var groupCandidate: String?
    /// Where the rows would land if the drag were dropped now — one list per section. Never
    /// written to the configuration until the drop lands.
    private var previewPinned: [DockEntry]?
    private var previewRunning: [String]?
    /// The last thing the drag was understood to mean, so the same intent is never acted on twice
    /// (D103).
    @ObservationIgnored private var lastIntent: (target: String, intent: DragIntent)?
    /// Where a reorder would put the dragged row: the caret drawn between two rows (M24). Set only
    /// while a reorder is what the drag means — a group candidate draws a ring instead.
    public private(set) var dropIndicator: DropIndicator?
    /// Opens a group's popover mid-drag, so the drag can carry on into it (M24).
    @ObservationIgnored private var springTask: Task<Void, Never>?

    /// Where the insertion caret goes: on one edge of a row that is still drawn.
    public struct DropIndicator: Equatable, Sendable {
        public let row: String
        public let after: Bool
    }

    /// Which edge of `id` the caret belongs on, if either: `false` before it, `true` after it, `nil`
    /// for every other row and whenever the drag means something else.
    public func dropEdge(for id: String) -> Bool? {
        guard let dropIndicator, dropIndicator.row == id else { return nil }
        return dropIndicator.after
    }

    /// How long a drag rests on a group before the group opens under it. Longer than the grouping
    /// zone needs, because spring-loading is the *second* thing this gesture can mean.
    static let springDwell = Duration.milliseconds(900)

    /// Applications that have been asked to launch and have not appeared yet (M24). The row is
    /// dimmed while it is in here, which is the only honest answer to "did my click work".
    public private(set) var launching: Set<String> = []

    /// iOS's jiggle mode: every pinned row grows a minus badge and shakes (M24, D107). Entered by
    /// pressing and holding a row, left by clicking anything else.
    public private(set) var isEditing = false
    @ObservationIgnored private var editingIdleTask: Task<Void, Never>?

    /// Extent of the screen the bar may use along its own axis, set by `PanelController` when it
    /// reframes. Zero until then, which reads as "no budget yet" and shows the limits alone.
    public var availableExtent: CGFloat = 0

    /// Whether the counts are the exact Accessibility ones. A badge that cannot be trusted is
    /// worse than no badge, so without Accessibility none is drawn (D61).
    public var windowCountsAreExact = false

    /// Window titles per application, filled when the pointer enters a row so the context menu —
    /// which `NSMenu` builds synchronously — never waits on Accessibility (D60).
    public private(set) var windowsByApplication: [String: [NexusWindow]] = [:]

    /// The Dock's own badge labels, per bundle identifier (M24, D106). Empty without Accessibility,
    /// which means no badges and nothing else.
    public private(set) var badges: [String: String] = [:]

    public func badge(for identifier: String) -> String? { badges[identifier] }

    /// A group wears the first badge any of its members has: nine icons behind one row, and the
    /// point of the badge is that something in there wants attention.
    public func badge(forGroup group: SidebarGroup) -> String? {
        group.items.compactMap { badges[$0.id] }.first
    }

    public func setBadges(_ labels: [String: String]) {
        guard labels != badges else { return }
        badges = labels
    }


    /// The application whose window flyout is open, if any.
    public private(set) var flyoutTarget: ApplicationIdentity?

    @ObservationIgnored private let applications: any ApplicationServing
    @ObservationIgnored private let configuration: ConfigurationController
    @ObservationIgnored private let events: EventBus
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    /// Everything a change to which resizes the bar. `search.barStyle` is in here because the box
    /// costs three slots where the icon costs one (D90).
    @ObservationIgnored private var lastLayoutInputs:
        (AppearanceConfiguration, Bool, Bool, SearchBarStyle)?
    /// Every application the sidebar knows about, by bundle identifier, and the running ones in
    /// display order. The two row lists are composed from these.
    @ObservationIgnored private var items: [String: SidebarItem] = [:]
    @ObservationIgnored private var alphabeticalRunning: [String] = []
    @ObservationIgnored private var hoverPreviewTask: Task<Void, Never>?
    @ObservationIgnored private var folderHoverTask: Task<Void, Never>?

    /// Called whenever the number of rows or the appearance changes, so the panel can reframe.
    @ObservationIgnored public var layoutDidChange: (() -> Void)?
    /// Injected by the composition root at Milestone 5; the search row is hidden until then.
    @ObservationIgnored public var openSearch: (() -> Void)?
    /// Injected at Milestone 11; the launcher row is hidden until then, and stays hidden unless
    /// `general.showStartMenu` is on.
    @ObservationIgnored public var openStartMenu: (() -> Void)?
    /// Injected at Milestone 4; shows the window flyout for an application.
    @ObservationIgnored public var showWindows: ((ApplicationIdentity) -> Void)?
    /// Starts the flyout's grace period — the pointer left a row, but it may be on its way to the
    /// flyout itself.
    @ObservationIgnored public var scheduleFlyoutHide: (() -> Void)?
    /// The same, for a folder stack opened by hovering its row (F2).
    @ObservationIgnored public var scheduleFolderHide: (() -> Void)?
    /// Pointer entered or left the sidebar; drives the auto-hide grace timer.
    @ObservationIgnored public var onHoverChange: ((Bool) -> Void)?
    /// Recomputes window counts. Called when the pointer enters the sidebar, because macOS
    /// publishes no notification for another application opening a window.
    @ObservationIgnored public var refreshWindowCounts: (() -> Void)?
    /// Re-reads the Dock's badges (D106). Called on the same events as the window counts: the Dock
    /// publishes no notification for a badge changing, and a timer for a decoration is a timer too
    /// many.
    @ObservationIgnored public var refreshBadges: (() -> Void)?
    /// Asks for one application's windows; the answer arrives via `setWindows(_:for:)`.
    @ObservationIgnored public var loadWindows: ((ApplicationIdentity) -> Void)?
    /// Raises one window. Injected at Milestone 9; without it the menu shows no window section.
    @ObservationIgnored public var activateWindow: ((WindowIdentity) -> Void)?
    /// Opens a group's popover. Injected at Milestone 13.
    @ObservationIgnored public var showGroup: ((SidebarGroup) -> Void)?
    /// Opens a pinned folder's stack, the same way `showGroup` opens a group (M21).
    @ObservationIgnored public var showFolder: ((SidebarFolder) -> Void)?
    /// Transport controls and the now-playing flyout. Injected at Milestone 15; without them the
    /// row is absent whatever the setting says.
    @ObservationIgnored public var mediaCommand: ((MediaKey) -> Void)?
    /// Tells the service whether anybody is looking at the player, since that is what gates reading
    /// its position at all (M16).
    @ObservationIgnored public var setPlayerVisible: ((Bool) -> Void)?
    @ObservationIgnored public var seekPlayer: ((Double) -> Void)?
    /// Called after every row rebuild, so an open group popover can follow its group — or close,
    /// if the group has just been dissolved.
    @ObservationIgnored public var rowsDidChange: (() -> Void)?

    public init(
        applications: any ApplicationServing,
        configuration: ConfigurationController,
        events: EventBus
    ) {
        self.applications = applications
        self.configuration = configuration
        self.events = events
    }

    public func start() {
        let stream = events.events()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .configurationChanged:
                    self.configurationChanged()
                case .applicationLaunched, .applicationTerminated, .applicationActivated,
                     .applicationsChanged:
                    await self.refresh()
                case .windowsChanged:
                    // Accessibility is granted, so window opens and closes are observable —
                    // recompute the permission-free counts that drive the badges.
                    self.refreshWindowCounts?()
                default:
                    continue
                }
            }
        }
        Task { await refresh() }
        refreshTrash()
    }

    public func stop() {
        eventTask?.cancel()
        eventTask = nil
        hoverPreviewTask?.cancel()
        hoverPreviewTask = nil
        folderHoverTask?.cancel()
        folderHoverTask = nil
        springTask?.cancel()
        springTask = nil
        editingIdleTask?.cancel()
        editingIdleTask = nil
    }

    // MARK: - Rows

    /// The utility section — Trash, then Search — is always present: the Trash row does not
    /// depend on anything being injected, so this section never has fewer than one row.
    /// One entry per drawn section, in order — the six parts of the bar: launcher, pinned, running,
    /// now playing, Trash, Search. Empty sections are dropped by `SidebarLayout`, which is what puts
    /// a separator between exactly the parts that are there (D77).
    public var sectionRowCounts: [Int] {
        let zones = zones
        var counts: [Int] = []
        if showsStartMenuRow { counts.append(1) }
        counts.append(zones.pinnedRows)
        if behavior.showRunningApplications { counts.append(zones.runningRows) }
        if showsNowPlayingRow { counts.append(nowPlayingRowCount) }
        counts.append(1)                                    // Trash
        if openSearch != nil { counts.append(searchRowCount) }
        return counts
    }

    public var showsStartMenuRow: Bool { general.showStartMenu && openStartMenu != nil }

    /// Rows in the fixed tail: the now-playing row when there is something to show, Trash, and
    /// Search once it is injected. A row that is not there gives its slot back to the applications
    /// (D74).
    public var tailRowCount: Int {
        (showsNowPlayingRow ? nowPlayingRowCount : 0)
            + minimizedRowCount
            + 1
            + (openSearch == nil ? 0 : searchRowCount)
    }

    /// Rows the minimized section draws: none when it is switched off, when Accessibility is not
    /// granted (nothing to enumerate), or when nothing is minimized.
    public var minimizedRowCount: Int {
        guard behavior.showMinimizedWindows, activateWindow != nil else { return 0 }
        return min(minimized.count, Self.minimizedLimit)
    }

    public var showsMinimizedRows: Bool { minimizedRowCount > 0 }

    /// The rows actually drawn, which is the capped list.
    public var minimizedRows: [MinimizedWindow] {
        Array(minimized.prefix(minimizedRowCount))
    }

    /// How many slots the Search part takes: three when it is drawn as a box, one when it is an
    /// icon. Same trick as the wide player — one view across three rows' extent (D82) — so the
    /// layout maths stays row-based.
    public var searchRowCount: Int { isSearchFieldWide ? 3 : 1 }

    /// A box only where a box fits. A vertical bar is 64 points across, and three rows of *height*
    /// buy nothing a search box can use, so it stays an icon unless hover has expanded the bar.
    public var isSearchFieldWide: Bool {
        guard search.barStyle == .field else { return false }
        return !appearance.position.isVertical || isExpanded
    }

    public var showsNowPlayingRow: Bool {
        general.showNowPlaying && mediaCommand != nil && nowPlayingIsActive
    }

    /// How many rows' worth of bar the player takes: two when compact — artwork and the transport
    /// buttons — and four when wide, drawn as one inline player across them (M17).
    ///
    /// Counting it in rows is what keeps every other piece of layout maths row-based: the wide
    /// player is one view spanning four rows' extent, not a section with its own pitch.
    public var nowPlayingRowCount: Int { isMediaPlayerWide ? 4 : 2 }

    /// Wide only where wide fits. A vertical bar is 64 points across: four rows of *height* buy
    /// nothing a horizontal scrubber can use, so it stays compact unless hover has expanded it.
    public var isMediaPlayerWide: Bool {
        guard appearance.mediaWidth == .wide else { return false }
        return !appearance.position.isVertical || isExpanded
    }

    /// The sections that never scroll, each of which costs a separator: the launcher, then the
    /// tail's three parts.
    private var fixedSectionRows: [Int] {
        var rows: [Int] = []
        if showsStartMenuRow { rows.append(1) }
        if showsNowPlayingRow { rows.append(nowPlayingRowCount) }
        rows.append(1)                                      // Trash
        if showsMinimizedRows { rows.append(minimizedRowCount) }
        if openSearch != nil { rows.append(searchRowCount) }
        return rows
    }

    /// How the bar divides itself up (M14): a fixed head, a scrolling middle whose two sections
    /// have a row budget each, and a fixed tail that never scrolls away.
    public var zones: SidebarLayout.BarZones {
        SidebarLayout.zones(
            fixedRows: fixedSectionRows,
            pinnedRows: pinned.count,
            runningRows: behavior.showRunningApplications ? running.count : 0,
            appearance: appearance,
            // Before the first reframe there is no screen to measure. A large finite extent means
            // "everything fits" without pretending the screen is infinite, which no arithmetic
            // survives.
            available: availableExtent > 0 ? availableExtent : 100_000
        )
    }

    /// Section indices for the flyout anchor. `SidebarLayout` skips empty sections, so these are
    /// counted the same way.
    public var pinnedSectionIndex: Int { showsStartMenuRow ? 1 : 0 }
    /// The Search row is the last section when there is one at all — it is appended last and it is
    /// never empty, so it cannot be dropped by the empty-section filter.
    public var searchSectionIndex: Int? {
        guard openSearch != nil else { return nil }
        return sectionRowCounts.filter { $0 > 0 }.count - 1
    }
    public var runningSectionIndex: Int { pinnedSectionIndex + (pinned.isEmpty ? 0 : 1) }

    public var showsPlaceholder: Bool {
        pinned.isEmpty && (running.isEmpty || !behavior.showRunningApplications)
    }

    public func refresh() async {
        let identifiers = pinnedEntries.flatMap(\.applications)
        let runningApplications = await applications.runningApplications()

        var resolved: [String: SidebarItem] = [:]
        for application in runningApplications {
            resolved[application.identity.bundleIdentifier] = SidebarItem(application: application, isPinned: false)
        }
        for identifier in identifiers where resolved[identifier] == nil {
            let identity = ApplicationIdentity(bundleIdentifier: identifier)
            if let metadata = await applications.application(for: identity) {
                resolved[identifier] = SidebarItem(application: metadata, isPinned: true)
            }
        }

        items = resolved
        // Whatever has turned up is not launching any more, and its row stops being dimmed (M24).
        launching = launching.filter { resolved[$0]?.isRunning != true }
        alphabeticalRunning = runningApplications
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(\.identity.bundleIdentifier)
        rebuildRows()
        // An application launching or quitting is the other moment a badge appears or goes (D106).
        refreshBadges?()
    }

    /// The dock the pinned section shows: the stored one, or the drag preview while one is in
    /// flight. A running application being dragged into the section appears here before it is
    /// pinned, which is what lets the rows move under the drag (D59).
    private var pinnedEntries: [DockEntry] {
        previewPinned ?? configuration.configuration.pinnedEntries
    }

    private var groupCapacity: Int { behavior.groupCapacity }

    /// The running section's order: the applications the user has dragged, in the order they put
    /// them, then everything else alphabetically. An application nobody has moved keeps its
    /// alphabetical place, so the section does not shuffle itself around.
    private var runningIdentifiers: [String] {
        if let previewRunning { return previewRunning }
        let stored = configuration.configuration.runningApplicationOrder
        let pinnedSet = Set(configuration.configuration.pinnedApplications)  // groups included
        let known = Set(alphabeticalRunning)
        let moved = stored.filter { known.contains($0) && !pinnedSet.contains($0) }
        let rest = alphabeticalRunning.filter { !moved.contains($0) && !pinnedSet.contains($0) }
        return moved + rest
    }

    /// Composes the two row lists from the resolved items. Synchronous on purpose: a drag has to
    /// reorder the rows in the same run loop turn as the pointer moves.
    private func rebuildRows() {
        let entries = pinnedEntries
        let pinnedSet = Set(entries.flatMap(\.applications))
        var resolvedPinned: [SidebarRow] = []
        for entry in entries {
            switch entry {
            case .application(let identifier):
                guard var item = items[identifier] else { continue }
                item.isPinned = true
                resolvedPinned.append(.application(item))
            case .folder(let path):
                let url = URL(fileURLWithPath: path)
                resolvedPinned.append(
                    .folder(SidebarFolder(path: path, name: FolderStackService.displayName(of: url)))
                )
            case .group(let group):
                let members = group.applications
                    .compactMap { identifier -> SidebarItem? in
                        guard var item = items[identifier] else { return nil }
                        item.isPinned = true
                        return item
                    }
                // A group whose applications have all been uninstalled disappears without taking
                // the dock with it.
                guard !members.isEmpty else { continue }
                resolvedPinned.append(.group(SidebarGroup(group: group, items: members)))
            }
        }
        let resolvedRunning = runningIdentifiers
            .filter { !pinnedSet.contains($0) }
            .compactMap { items[$0] }

        let layoutChanged = resolvedPinned.count != pinned.count
            || resolvedRunning.count != running.count
        pinned = resolvedPinned
        running = resolvedRunning
        rowsDidChange?()
        if layoutChanged {
            Log.sidebar.notice(
                "Sidebar rows: \(resolvedPinned.count, privacy: .public) pinned, \(resolvedRunning.count, privacy: .public) running (showRunningApplications=\(self.behavior.showRunningApplications, privacy: .public))"
            )
            layoutDidChange?()
        }
    }

    public func configurationChanged() {
        if !behavior.hoverExpand { isExpanded = false }
        let inputs = (
            appearance,
            behavior.showRunningApplications,
            behavior.hoverExpand,
            search.barStyle
        )
        let changed = lastLayoutInputs.map { $0 != inputs } ?? true
        lastLayoutInputs = inputs
        Task { await refresh() }
        if changed { layoutDidChange?() }
    }

    // MARK: - Actions

    public func activateOrLaunch(_ item: SidebarItem) {
        if behavior.clickBehavior == .showWindowList, item.isRunning, showWindows != nil {
            openFlyout(for: item.identity)
            return
        }
        if !item.isRunning { markLaunching(item.id) }
        Task { [applications] in
            if item.isRunning {
                try? await applications.activate(item.identity)
            } else {
                try? await applications.launch(item.identity)
            }
        }
    }

    /// Dims the row until the application shows up (M24). Nothing else tells the user their click
    /// landed: a cold launch can take five seconds, and an icon that does not react reads as a
    /// click that missed.
    private func markLaunching(_ identifier: String) {
        launching.insert(identifier)
        Task { [weak self] in
            // A launch that fails, or an application that never registers as running, must not
            // leave a row dimmed for the rest of the session.
            try? await Task.sleep(for: .seconds(15))
            self?.launching.remove(identifier)
        }
    }

    public func isLaunching(_ identifier: String) -> Bool { launching.contains(identifier) }

    /// Pins an application. With category suggestions on (F3) it goes into the group its category
    /// already has, if there is one — which is where the user put the last one.
    public func pin(_ identifier: String) {
        guard !configuration.configuration.pinnedApplications.contains(identifier) else { return }
        if let existing = categoryGroup(for: identifier), group(identifier, with: existing.id) { return }
        setEntries(configuration.configuration.pinnedEntries + [.application(identifier)])
        Log.sidebar.notice("Pinned \(identifier, privacy: .public)")
    }

    /// Removes an application from the dock, whether it sits in a slot of its own or in a group.
    public func unpin(_ identifier: String) {
        var entries = configuration.configuration.pinnedEntries
        for index in entries.indices {
            guard case .group(var group) = entries[index],
                  group.applications.contains(identifier)
            else { continue }
            group.applications.removeAll { $0 == identifier }
            entries[index] = .group(group)
        }
        entries.removeAll { $0 == .application(identifier) }
        setEntries(entries)
        Log.sidebar.notice("Unpinned \(identifier, privacy: .public)")
    }

    /// Moves the slot holding `identifier` so it sits immediately before `target`'s slot. Both
    /// must already be in the dock; anything else (a Finder drag arriving as a string, say) is
    /// ignored.
    public func movePinned(_ identifier: String, before target: String) {
        var entries = configuration.configuration.pinnedEntries
        guard identifier != target,
              let from = entries.firstIndex(where: { $0.id == identifier }),
              entries.contains(where: { $0.id == target })
        else { return }
        let moved = entries.remove(at: from)
        guard let insertion = entries.firstIndex(where: { $0.id == target }) else { return }
        entries.insert(moved, at: insertion)
        setEntries(entries)
    }

    /// Writes the dock, repaired: over-full groups trimmed, duplicates dropped, a group of one
    /// dissolved back into an application.
    private func setEntries(_ entries: [DockEntry]) {
        let repaired = entries.repaired(capacity: groupCapacity)
        configuration.update { $0.pinnedEntries = repaired }
        // Synchronously, like a drag: the rows must not wait for the configuration event to come
        // back round, or the bar shows the dock as it was for a frame.
        rebuildRows()
    }

    // MARK: - Groups

    /// Puts `identifier` together with whatever `target` is: two applications become a new group
    /// named after what they have in common, and an application dropped on a group joins it.
    /// Refused — visibly, by the drop never being offered — when the group is full (M13).
    ///
    /// A target that is only *running* is pinned on the way (D103): two loose icons making a folder
    /// is how everybody expects grouping to work, and refusing it because neither was pinned yet is
    /// a rule the bar cannot explain.
    @discardableResult
    public func group(_ identifier: String, with target: String) -> Bool {
        guard identifier != target, items[identifier] != nil else { return false }
        var entries = configuration.configuration.pinnedEntries
        if !entries.contains(where: { $0.id == target }) {
            guard items[target] != nil, !target.hasPrefix(DockEntry.identifierPrefix) else { return false }
            entries.append(.application(target))
        }
        guard let targetIndex = entries.firstIndex(where: { $0.id == target }) else { return false }

        switch entries[targetIndex] {
        case .application(let existing):
            guard existing != identifier else { return false }
            let members = [existing, identifier]
            entries[targetIndex] = .group(
                ApplicationGroup(name: suggestedName(for: members), applications: members)
            )
        case .group(var group):
            guard group.applications.count < groupCapacity,
                  !group.applications.contains(identifier)
            else { return false }
            group.applications.append(identifier)
            entries[targetIndex] = .group(group)
        case .folder:
            // A group is a group of applications (M13). Dropping something on a folder reorders it.
            return false
        }
        // Wherever the dragged application was — its own slot, or another group — it is not there
        // any more.
        entries = Self.removing(identifier, from: entries, keeping: targetIndex)
        setEntries(entries)
        Log.sidebar.notice("Grouped \(identifier, privacy: .public) into \(target, privacy: .public)")
        return true
    }

    /// Whether a row will accept being grouped with what is being dragged: an application onto
    /// another application — pinned or merely running (D103) — or onto a group with room left.
    public func canGroup(_ identifier: String, with target: String) -> Bool {
        guard identifier != target,
              !identifier.hasPrefix(DockEntry.identifierPrefix),
              items[identifier] != nil
        else { return false }
        guard let entry = configuration.configuration.pinnedEntries.first(where: { $0.id == target })
        else {
            // Not in the dock at all: a running row, which grouping pins as it goes.
            return items[target] != nil && !target.hasPrefix(DockEntry.identifierPrefix)
        }
        switch entry {
        case .application(let existing):
            return existing != identifier
        case .group(let group):
            return group.applications.count < groupCapacity
                && !group.applications.contains(identifier)
        case .folder:
            return false
        }
    }

    /// Takes an application out of its group and gives it a slot of its own, right after it.
    /// The group dissolves if that leaves one member behind.
    public func removeFromGroup(_ identifier: String) {
        var entries = configuration.configuration.pinnedEntries
        guard let index = entries.firstIndex(where: { $0.group?.applications.contains(identifier) == true }),
              case .group(var group) = entries[index]
        else { return }
        group.applications.removeAll { $0 == identifier }
        entries[index] = .group(group)
        entries.insert(.application(identifier), at: index + 1)
        setEntries(entries)
    }

    /// Dissolves a group, leaving its applications pinned in its place and in its order.
    public func ungroup(_ id: String) {
        var entries = configuration.configuration.pinnedEntries
        guard let index = entries.firstIndex(where: { $0.id == id }),
              case .group(let group) = entries[index]
        else { return }
        entries.replaceSubrange(index...index, with: group.applications.map { .application($0) })
        setEntries(entries)
    }

    /// Removes a group and everything in it from the dock.
    public func unpinGroup(_ id: String) {
        setEntries(configuration.configuration.pinnedEntries.filter { $0.id != id })
    }

    /// A group's colour and emoji (D108). `nil` for either means "none", which is what a group has
    /// until somebody picks one, and what the "no colour" swatch puts back.
    public func setGroupStyle(_ id: String, tint: GroupTint?, emoji: String?) {
        var entries = configuration.configuration.pinnedEntries
        guard let index = entries.firstIndex(where: { $0.id == id }),
              case .group(var group) = entries[index]
        else { return }
        group.tint = tint
        group.emoji = ApplicationGroup.trimmedEmoji(emoji)
        entries[index] = .group(group)
        setEntries(entries)
    }

    public func renameGroup(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var entries = configuration.configuration.pinnedEntries
        guard let index = entries.firstIndex(where: { $0.id == id }),
              case .group(var group) = entries[index]
        else { return }
        group.name = trimmed.isEmpty ? ApplicationCategory.fallbackName : trimmed
        entries[index] = .group(group)
        setEntries(entries)
    }

    public func isInGroup(_ identifier: String) -> Bool {
        configuration.configuration.pinnedEntries
            .contains { $0.group?.applications.contains(identifier) == true }
    }

    public func openGroup(_ group: SidebarGroup) {
        showGroup?(group)
    }

    // MARK: - Keyboard navigation (M23)

    /// Everything the keyboard can land on, in drawing order: the launcher, the dock, the running
    /// applications, the minimized windows, Trash, Search. The now-playing row is deliberately not
    /// here — its buttons are three targets in one row, and the transport keys already reach the
    /// player from anywhere.
    public var focusableRowIDs: [String] {
        var ids: [String] = []
        if showsStartMenuRow { ids.append(Self.startMenuRowID) }
        ids += pinned.map(\.id)
        if behavior.showRunningApplications { ids += running.map(\.id) }
        ids += minimizedRows.map(\.id)
        ids.append(Self.trashRowID)
        if openSearch != nil { ids.append(Self.searchRowID) }
        return ids
    }

    public static let startMenuRowID = "row:startMenu"
    public static let trashRowID = "row:trash"
    public static let searchRowID = "row:search"

    public var isKeyboardNavigating: Bool { focusedRowID != nil }

    /// Enters keyboard mode on the first row, or leaves it if it is already on.
    public func toggleKeyboardNavigation() {
        if isKeyboardNavigating { endKeyboardNavigation() } else { beginKeyboardNavigation() }
    }

    public func beginKeyboardNavigation() {
        guard let first = focusableRowIDs.first else { return }
        focusedRowID = first
        setKeyboardFocus?(true)
    }

    public func endKeyboardNavigation() {
        guard focusedRowID != nil else { return }
        focusedRowID = nil
        setKeyboardFocus?(false)
    }

    /// Walks the rows. Stops at each end rather than wrapping: a bar is a line, and wrapping from
    /// Search back to the launcher reads as a jump rather than a move.
    public func moveFocus(by delta: Int) {
        let ids = focusableRowIDs
        guard let current = focusedRowID, let index = ids.firstIndex(of: current) else {
            beginKeyboardNavigation()
            return
        }
        let next = min(max(index + delta, 0), ids.count - 1)
        focusedRowID = ids[next]
    }

    public func focusFirstRow() {
        guard isKeyboardNavigating, let first = focusableRowIDs.first else { return }
        focusedRowID = first
    }

    public func focusLastRow() {
        guard isKeyboardNavigating, let last = focusableRowIDs.last else { return }
        focusedRowID = last
    }

    /// Does what clicking the focused row does, then leaves keyboard mode — the row's own action
    /// is usually to put another application in front, and holding the keyboard after that would
    /// take it from the thing the user just asked for.
    public func activateFocusedRow() {
        guard let id = focusedRowID else { return }
        endKeyboardNavigation()
        switch id {
        case Self.startMenuRowID: openStartMenu?()
        case Self.trashRowID: openTrash()
        case Self.searchRowID: openSearch?()
        default:
            if let row = pinned.first(where: { $0.id == id }) {
                switch row {
                case .application(let item): activateOrLaunch(item)
                case .group(let group): openGroup(group)
                case .folder(let folder): openFolder(folder)
                }
            } else if let item = running.first(where: { $0.id == id }) {
                activateOrLaunch(item)
            } else if let window = minimized.first(where: { $0.id == id }) {
                restore(window)
            }
        }
    }

    // MARK: - Folders

    public func openFolder(_ folder: SidebarFolder) {
        showFolder?(folder)
    }

    /// How long the pointer rests on a folder before its stack opens (F2). Shorter than the window
    /// flyout's default: a folder has no other way of showing what is in it, so the answer to
    /// hovering one is "yes, and quickly".
    static let folderHoverDelay = Duration.milliseconds(400)

    /// Pointer entered or left a folder row. With the preference on, resting on one opens the stack
    /// without a click; sweeping past it opens nothing.
    public func folderHoverChanged(_ folder: SidebarFolder, hovering: Bool) {
        folderHoverTask?.cancel()
        folderHoverTask = nil
        guard behavior.folderHoverPreview, showFolder != nil else { return }
        guard hovering else {
            scheduleFolderHide?()
            return
        }
        folderHoverTask = Task { [weak self] in
            try? await Task.sleep(for: Self.folderHoverDelay)
            guard !Task.isCancelled else { return }
            self?.openFolder(folder)
        }
    }

    public func unpinFolder(_ id: String) {
        setEntries(configuration.configuration.pinnedEntries.filter { $0.id != id })
    }

    /// Pins a folder at the end of the dock. Idempotent: a folder already on the bar keeps its
    /// slot rather than gaining a second one.
    @discardableResult
    public func pinFolder(at url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        var entries = configuration.configuration.pinnedEntries
        guard !entries.contains(.folder(path)) else { return false }
        entries.append(.folder(path))
        setEntries(entries)
        Log.sidebar.notice("Pinned folder \(path, privacy: .public)")
        return true
    }

    /// The name a new group gets: whatever category most of its members declare (M13).
    private func suggestedName(for members: [String]) -> String {
        ApplicationCategory.groupName(
            for: members.map { identifier in
                items[identifier].flatMap { ApplicationCategory.category(of: $0.bundleURL) }
            },
            names: members.compactMap { items[$0]?.name }
        )
    }

    /// Drops `identifier` from every slot except the one at `keeping`, which is where it has just
    /// been put.
    private static func removing(
        _ identifier: String,
        from entries: [DockEntry],
        keeping index: Int
    ) -> [DockEntry] {
        var result = entries
        for position in result.indices where position != index {
            switch result[position] {
            case .application(let existing) where existing == identifier:
                result[position] = .application("")     // repaired() drops it
            case .group(var group) where group.applications.contains(identifier):
                group.applications.removeAll { $0 == identifier }
                result[position] = .group(group)
            default:
                continue
            }
        }
        return result
    }

    // MARK: - Dragging

    /// A row started moving — pinned or running. A running application is previewed inside the
    /// pinned section as soon as the drag reaches it, and dropping is what pins it there.
    public func beginDrag(_ identifier: String) {
        // An application the bar knows, or any slot the dock holds. Checking the *dock* rather than
        // the "group:" prefix is what lets a folder row be dragged at all: it wears a "folder:" id,
        // and a prefix check for one of the two silently refused the other.
        guard items[identifier] != nil
                || configuration.configuration.pinnedEntries.contains(where: { $0.id == identifier })
        else { return }
        draggingIdentifier = identifier
        lastIntent = nil
        dropIndicator = nil
        // A member dragged out of a group leaves it for the duration of the drag: the preview then
        // treats it like any other row, and dropping it anywhere but back on the group is what
        // takes it out for good.
        previewPinned = Self.leavingGroups(identifier, in: pinnedEntries)
        previewRunning = runningIdentifiers
    }

    private static func leavingGroups(_ identifier: String, in entries: [DockEntry]) -> [DockEntry] {
        entries.map { entry in
            guard case .group(var group) = entry,
                  group.applications.contains(identifier)
            else { return entry }
            group.applications.removeAll { $0 == identifier }
            return .group(group)
        }
    }

    /// What a drag over a row means, decided by *where* in the row it is (D103).
    enum DragIntent: Equatable {
        /// The middle of a row that can take the dragged application: put these together.
        case group
        case insertBefore
        case insertAfter
    }

    /// The middle band of a row that reads as grouping rather than reordering. Wide enough to hit
    /// while the pointer is still moving, narrow enough that both ends stay easy reorder targets.
    static let groupZone: ClosedRange<CGFloat> = 0.3...0.7

    /// The drag is over `target`, at `location` inside it: show what dropping here would do.
    ///
    /// `location` is normalised 0…1 from the row's top-left corner, so `y` runs along a vertical
    /// bar and `x` along a horizontal one. The middle of the row groups; either end reorders, into
    /// whichever section `target` belongs to — which is what makes dragging across the separator
    /// pin or unpin a row.
    public func dragMoved(over target: String, at location: CGPoint) {
        guard let dragged = draggingIdentifier, dragged != target else { return }
        let fraction = appearance.position.isVertical ? location.y : location.x
        let intent: DragIntent
        if Self.groupZone.contains(fraction), canGroup(dragged, with: target) {
            intent = .group
        } else {
            intent = fraction < 0.5 ? .insertBefore : .insertAfter
        }

        // Hysteresis. Every preview change moves the rows under a pointer that has not moved, so
        // the next `draggingUpdated` arrives with fresh coordinates for a gesture that has not
        // changed its mind. Acting on the same intent twice is what made the bar shiver.
        if let last = lastIntent, last.target == target, last.intent == intent { return }
        lastIntent = (target, intent)

        switch intent {
        case .group:
            // The preview is deliberately left exactly as it is: the target grows a ring, and
            // nothing moves. A reorder here is what used to snatch the target out from under the
            // pointer the moment it was chosen.
            groupCandidate = target
            dropIndicator = nil
            springLoad(target)
        case .insertBefore, .insertAfter:
            groupCandidate = nil
            springTask?.cancel()
            springTask = nil
            dropIndicator = DropIndicator(row: target, after: intent == .insertAfter)
            reorderPreview(dragged, target: target, after: intent == .insertAfter)
        }
    }

    /// A drag resting on a group opens it, so it can be carried on inside and dropped between two
    /// members — Finder's spring-loaded folders, and iOS's (M24).
    private func springLoad(_ target: String) {
        springTask?.cancel()
        guard let group = pinned.first(where: { $0.id == target })?.group, showGroup != nil else {
            springTask = nil
            return
        }
        springTask = Task { [weak self] in
            try? await Task.sleep(for: Self.springDwell)
            guard !Task.isCancelled, let self, self.groupCandidate == target else { return }
            self.openGroup(group)
        }
    }

    /// Moves the preview so the dragged row sits beside `target`. Nothing is stored until the drop.
    private func reorderPreview(_ dragged: String, target: String, after: Bool) {
        guard var pinnedOrder = previewPinned, var runningOrder = previewRunning else { return }
        let moved = pinnedOrder.first { $0.id == dragged } ?? .application(dragged)
        pinnedOrder.removeAll { $0.id == dragged }
        runningOrder.removeAll { $0 == dragged }

        // The index is taken *after* the removal, so "before" and "after" mean what they say
        // whichever direction the row came from.
        if let index = pinnedOrder.firstIndex(where: { $0.id == target }) {
            pinnedOrder.insert(moved, at: after ? index + 1 : index)
        } else if let index = runningOrder.firstIndex(of: target) {
            runningOrder.insert(dragged, at: after ? index + 1 : index)
        } else {
            return
        }

        guard pinnedOrder != previewPinned || runningOrder != previewRunning else { return }
        previewPinned = pinnedOrder
        previewRunning = runningOrder
        rebuildRows()
    }

    /// The drag ended. A cancelled drag — dropped outside, or on nothing — must leave the stored
    /// order exactly as it was.
    public func endDrag(commit: Bool) {
        let pinnedOrder = previewPinned
        let runningOrder = previewRunning
        let dragged = draggingIdentifier
        let candidate = groupCandidate
        lastIntent = nil
        dropIndicator = nil
        springTask?.cancel()
        springTask = nil
        draggingIdentifier = nil
        groupCandidate = nil
        previewPinned = nil
        previewRunning = nil

        // Letting go over the middle of a row means "put these together", not "move me here".
        if commit, let dragged, let candidate {
            group(dragged, with: candidate)
            rebuildRows()
            return
        }
        guard commit, let pinnedOrder, let runningOrder else {
            rebuildRows()
            return
        }
        let stored = configuration.configuration
        guard pinnedOrder != stored.pinnedEntries || runningOrder != runningIdentifiers else {
            rebuildRows()
            return
        }
        configuration.update {
            $0.pinnedEntries = pinnedOrder.repaired(capacity: self.groupCapacity)
            $0.runningApplicationOrder = runningOrder
        }
        rebuildRows()
    }

    /// The drag was let go outside the bar (F1, D105). A pinned row leaves the dock — the Dock's own
    /// gesture, and the reason it is worth having: the alternative is a context menu for something
    /// the hand has already done. A running row has nothing to leave, so it is a cancel.
    ///
    /// Returns whether anything was unpinned, so the caller can put the puff of smoke where the
    /// pointer let go.
    @discardableResult
    public func dragDroppedOutside() -> Bool {
        guard let dragged = draggingIdentifier else { return false }
        let entries = configuration.configuration.pinnedEntries
        let wasPinned = entries.contains { $0.id == dragged || $0.applications.contains(dragged) }
        endDrag(commit: false)
        guard wasPinned else { return false }
        if dragged.hasPrefix(DockEntry.identifierPrefix) {
            unpinGroup(dragged)
        } else if dragged.hasPrefix(DockEntry.folderPrefix) {
            unpinFolder(dragged)
        } else {
            unpin(dragged)
        }
        Log.sidebar.notice("Dragged \(dragged, privacy: .public) off the bar")
        return true
    }

    /// A row was dropped on one of a group's own tiles, inside the open popover (P2): it joins the
    /// group *there*, rather than at the end.
    @discardableResult
    public func dropIntoGroup(_ identifier: String, groupID: String, before member: String) -> Bool {
        guard !identifier.hasPrefix(DockEntry.identifierPrefix),
              identifier != member,
              items[identifier] != nil
        else { return false }
        var entries = configuration.configuration.pinnedEntries
        guard let index = entries.firstIndex(where: { $0.id == groupID }),
              case .group(var group) = entries[index]
        else { return false }
        group.applications.removeAll { $0 == identifier }
        guard group.applications.count < groupCapacity else { return false }
        let insertion = group.applications.firstIndex(of: member) ?? group.applications.count
        group.applications.insert(identifier, at: insertion)
        entries[index] = .group(group)
        entries = Self.removing(identifier, from: entries, keeping: index)
        setEntries(entries)
        Log.sidebar.notice("Dropped \(identifier, privacy: .public) into a group at \(insertion, privacy: .public)")
        return true
    }

    // MARK: - Edit mode (M24)

    /// Pressed and held. Every pinned row grows a minus badge and starts shaking, which is how iOS
    /// has said "you can take these out now" since 2008 (D107).
    public func beginEditing() {
        guard !isEditing else { return }
        isEditing = true
        armEditingTimeout()
    }

    public func endEditing() {
        guard isEditing else { return }
        editingIdleTask?.cancel()
        editingIdleTask = nil
        isEditing = false
    }

    /// Insurance, not a feature — the same shape the keyboard mode's timeout has (D99). A bar left
    /// jiggling because a click went somewhere unexpected is a bar that looks broken.
    private func armEditingTimeout() {
        editingIdleTask?.cancel()
        editingIdleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.endEditing()
        }
    }

    /// What the minus badge on a row does: whatever "not on the bar any more" means for that row.
    public func removeRow(_ id: String) {
        if id.hasPrefix(DockEntry.identifierPrefix) {
            unpinGroup(id)
        } else if id.hasPrefix(DockEntry.folderPrefix) {
            unpinFolder(id)
        } else {
            unpin(id)
        }
        if pinned.isEmpty { endEditing() }
    }

    // MARK: - Category groups (F3, D109)

    /// The group a category already has on the bar, if this application belongs to it. Nothing is
    /// created here and nothing is scanned: it is one look at the dock and one at the bundle.
    public func categoryGroup(for identifier: String) -> SidebarGroup? {
        guard behavior.suggestCategoryGroups,
              let item = items[identifier],
              let category = ApplicationCategory.category(of: item.bundleURL),
              let name = ApplicationCategory.displayName(for: category)
        else { return nil }
        return pinned.compactMap(\.group).first {
            $0.name == name && $0.items.count < groupCapacity && !$0.items.contains { $0.id == identifier }
        }
    }

    /// A row was dropped on `target`. A drag of the bar's own needs nothing here: its preview
    /// already says where the row goes, and `endDrag` is what commits it. This covers a drop that
    /// arrived without a preview — one from the group popover, or a drag begun before the row list
    /// was ready.
    public func dropPinned(_ identifier: String, on target: String) {
        guard draggingIdentifier == nil else { return }
        let entries = configuration.configuration.pinnedEntries
        guard identifier != target,
              entries.contains(where: { $0.id == target }),
              !entries.contains(where: { $0.applications.contains(identifier) })
        else { return }
        pin(identifier)
        movePinned(identifier, before: target)
    }

    /// Reorder by one slot; the same operation the context menu offers. `id` is a row — an
    /// application or a group.
    public func canMovePinned(_ id: String, by delta: Int) -> Bool {
        let entries = configuration.configuration.pinnedEntries
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        return entries.indices.contains(index + delta)
    }

    public func movePinned(_ id: String, by delta: Int) {
        var entries = configuration.configuration.pinnedEntries
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries.indices.contains(index + delta)
        else { return }
        let moved = entries.remove(at: index)
        entries.insert(moved, at: index + delta)
        setEntries(entries)
    }

    public func movePinnedToEnd(_ id: String) {
        var entries = configuration.configuration.pinnedEntries
        guard let from = entries.firstIndex(where: { $0.id == id }) else { return }
        let moved = entries.remove(at: from)
        entries.append(moved)
        setEntries(entries)
    }

    // MARK: - Now playing

    /// The service pushed a new state. A row appearing or disappearing changes the bar's length,
    /// so the panel is told to reframe.
    public func nowPlayingChanged(
        _ playing: NowPlaying,
        isActive: Bool,
        players: [String] = [],
        position: MediaPosition? = nil
    ) {
        let wasShowing = showsNowPlayingRow
        nowPlaying = playing
        nowPlayingIsActive = isActive
        nowPlayingFallbackPlayer = players.first
        nowPlayingPosition = position
        if showsNowPlayingRow != wasShowing {
            layoutDidChange?()
            // A row that has appeared is a row somebody can see: that is what starts the one poll
            // Nexus allows itself (M16).
            setPlayerVisible?(showsNowPlayingRow)
        }
    }

    public func seekPlayback(to seconds: Double) { seekPlayer?(seconds) }

    public func togglePlayback() { mediaCommand?(.play) }
    public func nextTrack() { mediaCommand?(.next) }
    public func previousTrack() { mediaCommand?(.previous) }

    /// Artwork, or the player's own icon. Neither Music nor Spotify puts artwork in the
    /// notification, so in practice this is the icon — the one image macOS will hand over for
    /// free (D75).
    public func nowPlayingArtwork(size: CGFloat) -> NSImage {
        let identifier = nowPlaying.playerBundleIdentifier ?? nowPlayingFallbackPlayer
        if let identifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            return IconCache.shared.icon(for: url, size: size)
        }
        let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        return symbol ?? NSImage()
    }

    // MARK: - Hover previews

    /// Pointer entered or left one row. Opens that application's window flyout after
    /// `hoverPreviewDelay`, so sweeping the length of the bar opens nothing (M10).
    public func rowHoverChanged(_ item: SidebarItem, hovering: Bool) {
        hoverPreviewTask?.cancel()
        hoverPreviewTask = nil

        guard hovering else {
            scheduleFlyoutHide?()
            return
        }
        if item.isRunning { prefetchWindows(item.identity) }
        guard behavior.hoverPreview, item.isRunning, showWindows != nil else { return }

        // A flyout is already open: switching rows is instant. Paying the delay again per row is
        // what makes a hover dock feel sticky.
        guard flyoutTarget == nil else {
            openFlyout(for: item.identity)
            return
        }
        let delay = behavior.hoverPreviewDelay
        hoverPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.openFlyout(for: item.identity)
        }
    }

    public func openFlyout(for identity: ApplicationIdentity) {
        flyoutTarget = identity
        showWindows?(identity)
    }

    /// The flyout went away — by dismissal, by a click, or because its application quit.
    public func flyoutClosed() {
        hoverPreviewTask?.cancel()
        hoverPreviewTask = nil
        flyoutTarget = nil
    }

    // MARK: - Windows

    /// Warms the cache the context menu reads. Called on hover, so the AX traffic follows the
    /// pointer rather than a timer.
    public func prefetchWindows(_ identity: ApplicationIdentity) {
        guard activateWindow != nil else { return }
        loadWindows?(identity)
    }

    /// Every window in the system, from the same enumeration that refreshes the counts. The
    /// minimized ones keep the order they already had, and the ones that are new to the list go to
    /// the front — the window you just put down is the one you reach for.
    public func setAllWindows(_ windows: [NexusWindow]) {
        let minimizedNow = windows.filter(\.isMinimized)
        let byID = Dictionary(uniqueKeysWithValues: minimizedNow.map { ($0.id, $0) })
        var updated: [MinimizedWindow] = []
        for existing in minimized {
            guard let window = byID[existing.id] else { continue }
            updated.append(drawable(window))
        }
        let known = Set(updated.map(\.id))
        for window in minimizedNow where !known.contains(window.id) {
            updated.insert(drawable(window), at: 0)
        }
        guard updated != minimized else { return }
        let countChanged = min(updated.count, Self.minimizedLimit) != minimizedRowCount
        minimized = updated
        if countChanged { layoutDidChange?() }
    }

    private func drawable(_ window: NexusWindow) -> MinimizedWindow {
        let identifier = window.identity.owner.bundleIdentifier
        return MinimizedWindow(
            identity: window.identity,
            title: window.title,
            applicationName: window.applicationName.isEmpty
                ? (items[identifier]?.name ?? identifier)
                : window.applicationName,
            bundleURL: items[identifier]?.bundleURL
        )
    }

    /// Puts a minimized window back. The same call the flyout's rows make: `WindowService.activate`
    /// clears `AXMinimized`, raises the window and activates its application.
    public func restore(_ window: MinimizedWindow) {
        activateWindow?(window.identity)
    }

    public func setWindows(_ windows: [NexusWindow], for identity: ApplicationIdentity) {
        windowsByApplication[identity.bundleIdentifier] = windows
    }

    public func windows(for identity: ApplicationIdentity) -> [NexusWindow] {
        guard activateWindow != nil else { return [] }
        return windowsByApplication[identity.bundleIdentifier] ?? []
    }

    // MARK: - Trash

    /// macOS publishes no Trash-changed notification, so this is sampled on the same user event
    /// that refreshes window counts: the pointer entering the sidebar. Two `stat` calls, no
    /// permission (D58).
    public func refreshTrash() {
        let empty = TrashService.isEmpty
        guard empty != trashIsEmpty else { return }
        trashIsEmpty = empty
    }

    public func openTrash() {
        TrashService.open()
    }

    public func emptyTrash() {
        TrashService.empty()
        refreshTrash()
    }

    /// A drop from Finder. An `.app` is an application, any other directory is a folder stack
    /// (M21) — a bundle is a directory too, so the specific case wins — and a plain file is
    /// refused, since the bar has nothing to do with one.
    @discardableResult
    public func pinApplications(at urls: [URL]) -> Bool {
        var accepted = false
        for url in urls {
            if url.pathExtension == "app", let identifier = Bundle(url: url)?.bundleIdentifier {
                pin(identifier)
                accepted = true
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { continue }
            accepted = pinFolder(at: url) || accepted
        }
        return accepted
    }

    public func revealInFinder(_ item: SidebarItem) {
        Task { [applications] in await applications.revealInFinder(item.identity) }
    }

    public func quit(_ item: SidebarItem, force: Bool) {
        Task { [applications] in try? await applications.quit(item.identity, force: force) }
    }

    /// Single entry point for pointer enter/exit over the sidebar: drives hover-expand and,
    /// via `onHoverChange`, the auto-hide grace timer in `PanelController`.
    public func hoverChanged(_ hovering: Bool) {
        setExpanded(hovering)
        if hovering {
            refreshWindowCounts?()
            refreshBadges?()
            refreshTrash()
        }
        if !hovering { endEditing() }
        onHoverChange?(hovering)
    }

    public func setExpanded(_ expanded: Bool) {
        // Hover-expand is vertical-only (D53): a horizontal bar growing taller on hover would
        // shove every window on the screen.
        let next = behavior.hoverExpand && appearance.position.isVertical ? expanded : false
        guard next != isExpanded else { return }
        isExpanded = next
        layoutDidChange?()
    }
}
