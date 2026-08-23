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

/// One drawn row of the pinned section: an application, or a group of them (M13).
public enum SidebarRow: Identifiable, Equatable, Sendable {
    case application(SidebarItem)
    case group(SidebarGroup)

    public var id: String {
        switch self {
        case .application(let item): item.id
        case .group(let group): group.id
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

    /// Hover-expanded (names visible). Never true when `behavior.hoverExpand` is off.
    public var isExpanded = false

    /// What is playing, for the tail's now-playing row (M15). Empty until the service says
    /// otherwise, and the row is absent while it is.
    public private(set) var nowPlaying = NowPlaying()
    public private(set) var nowPlayingIsActive = false
    /// The application making the sound when no player published a track — a browser, say. It gives
    /// the row an icon instead of a blank square (D75).
    public private(set) var nowPlayingFallbackPlayer: String?

    /// Drives which Trash icon the utility row draws.
    public private(set) var trashIsEmpty = TrashService.isEmpty

    /// The row currently being dragged, so it can be drawn as a gap (D59).
    public private(set) var draggingIdentifier: String?
    /// The row the drag has been resting on long enough to mean "put these together" rather than
    /// "move me here" — highlighted while it holds, and what a drop acts on (M13).
    public private(set) var groupCandidate: String?
    /// Where the rows would land if the drag were dropped now — one list per section. Never
    /// written to the configuration until the drop lands.
    private var previewPinned: [DockEntry]?
    private var previewRunning: [String]?
    @ObservationIgnored private var dwellTask: Task<Void, Never>?
    @ObservationIgnored private var dwellTarget: String?

    /// How long a drag must rest on a row before it means grouping. Long enough that dragging
    /// past a row never groups by accident, short enough to feel like a decision.
    static let groupDwell = Duration.milliseconds(600)

    /// Extent of the screen the bar may use along its own axis, set by `PanelController` when it
    /// reframes. Zero until then, which reads as "no budget yet" and shows the limits alone.
    public var availableExtent: CGFloat = 0

    /// Whether the counts are the exact Accessibility ones. A badge that cannot be trusted is
    /// worse than no badge, so without Accessibility none is drawn (D61).
    public var windowCountsAreExact = false

    /// Window titles per application, filled when the pointer enters a row so the context menu —
    /// which `NSMenu` builds synchronously — never waits on Accessibility (D60).
    public private(set) var windowsByApplication: [String: [NexusWindow]] = [:]


    /// The application whose window flyout is open, if any.
    public private(set) var flyoutTarget: ApplicationIdentity?

    @ObservationIgnored private let applications: any ApplicationServing
    @ObservationIgnored private let configuration: ConfigurationController
    @ObservationIgnored private let events: EventBus
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var lastLayoutInputs: (AppearanceConfiguration, Bool, Bool)?
    /// Every application the sidebar knows about, by bundle identifier, and the running ones in
    /// display order. The two row lists are composed from these.
    @ObservationIgnored private var items: [String: SidebarItem] = [:]
    @ObservationIgnored private var alphabeticalRunning: [String] = []
    @ObservationIgnored private var hoverPreviewTask: Task<Void, Never>?

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
    /// Pointer entered or left the sidebar; drives the auto-hide grace timer.
    @ObservationIgnored public var onHoverChange: ((Bool) -> Void)?
    /// Recomputes window counts. Called when the pointer enters the sidebar, because macOS
    /// publishes no notification for another application opening a window.
    @ObservationIgnored public var refreshWindowCounts: (() -> Void)?
    /// Asks for one application's windows; the answer arrives via `setWindows(_:for:)`.
    @ObservationIgnored public var loadWindows: ((ApplicationIdentity) -> Void)?
    /// Raises one window. Injected at Milestone 9; without it the menu shows no window section.
    @ObservationIgnored public var activateWindow: ((WindowIdentity) -> Void)?
    /// Opens a group's popover. Injected at Milestone 13.
    @ObservationIgnored public var showGroup: ((SidebarGroup) -> Void)?
    /// Transport controls and the now-playing flyout. Injected at Milestone 15; without them the
    /// row is absent whatever the setting says.
    @ObservationIgnored public var mediaCommand: ((MediaKey) -> Void)?
    @ObservationIgnored public var showNowPlaying: ((NowPlaying) -> Void)?
    @ObservationIgnored public var hideNowPlaying: (() -> Void)?
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
    }

    // MARK: - Rows

    /// The utility section — Trash, then Search — is always present: the Trash row does not
    /// depend on anything being injected, so this section never has fewer than one row.
    public var sectionRowCounts: [Int] {
        let zones = zones
        var counts: [Int] = []
        if showsStartMenuRow { counts.append(1) }
        counts.append(zones.pinnedRows)
        if behavior.showRunningApplications { counts.append(zones.runningRows) }
        counts.append(tailRowCount)
        return counts
    }

    public var showsStartMenuRow: Bool { general.showStartMenu && openStartMenu != nil }

    /// Rows in the fixed tail: the now-playing row when there is something to show, Trash, and
    /// Search once it is injected. A row that is not there gives its slot back to the applications
    /// (D74).
    public var tailRowCount: Int { (showsNowPlayingRow ? 1 : 0) + (openSearch == nil ? 1 : 2) }

    public var showsNowPlayingRow: Bool {
        general.showNowPlaying && mediaCommand != nil && nowPlayingIsActive
    }

    /// How the bar divides itself up (M14): a fixed head, a scrolling middle whose two sections
    /// have a row budget each, and a fixed tail that never scrolls away.
    public var zones: SidebarLayout.BarZones {
        SidebarLayout.zones(
            headRows: showsStartMenuRow ? 1 : 0,
            pinnedRows: pinned.count,
            runningRows: behavior.showRunningApplications ? running.count : 0,
            tailRows: tailRowCount,
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
        alphabeticalRunning = runningApplications
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(\.identity.bundleIdentifier)
        rebuildRows()
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
                // The row being dragged onto another one is drawn nowhere: it is about to become
                // part of that row rather than a slot of its own.
                guard identifier != groupCandidateSource, var item = items[identifier] else { continue }
                item.isPinned = true
                resolvedPinned.append(.application(item))
            case .group(let group):
                let members = group.applications
                    .filter { $0 != groupCandidateSource }
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
            .filter { !pinnedSet.contains($0) && $0 != groupCandidateSource }
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
        let inputs = (appearance, behavior.showRunningApplications, behavior.hoverExpand)
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
        Task { [applications] in
            if item.isRunning {
                try? await applications.activate(item.identity)
            } else {
                try? await applications.launch(item.identity)
            }
        }
    }

    public func pin(_ identifier: String) {
        guard !configuration.configuration.pinnedApplications.contains(identifier) else { return }
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
    @discardableResult
    public func group(_ identifier: String, with target: String) -> Bool {
        guard identifier != target, items[identifier] != nil else { return false }
        var entries = configuration.configuration.pinnedEntries
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
        }
        // Wherever the dragged application was — its own slot, or another group — it is not there
        // any more.
        entries = Self.removing(identifier, from: entries, keeping: targetIndex)
        setEntries(entries)
        Log.sidebar.notice("Grouped \(identifier, privacy: .public) into \(target, privacy: .public)")
        return true
    }

    /// Whether a row will accept being grouped with what is being dragged: an application onto
    /// another application, or onto a group with room left.
    public func canGroup(_ identifier: String, with target: String) -> Bool {
        guard identifier != target,
              !identifier.hasPrefix(DockEntry.identifierPrefix),
              items[identifier] != nil,
              let entry = configuration.configuration.pinnedEntries.first(where: { $0.id == target })
        else { return false }
        switch entry {
        case .application(let existing):
            return existing != identifier
        case .group(let group):
            return group.applications.count < groupCapacity
                && !group.applications.contains(identifier)
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

    /// The name a new group gets: whatever category most of its members declare (M13).
    private func suggestedName(for members: [String]) -> String {
        ApplicationCategory.groupName(
            for: members.map { identifier in
                items[identifier].flatMap { ApplicationCategory.category(of: $0.bundleURL) }
            }
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
        guard items[identifier] != nil || identifier.hasPrefix(DockEntry.identifierPrefix) else { return }
        draggingIdentifier = identifier
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

    /// The application that is about to be swallowed by a group, so the rows stop drawing it in a
    /// slot of its own while the drag rests on its target.
    private var groupCandidateSource: String? {
        groupCandidate == nil ? nil : draggingIdentifier
    }

    /// The drag is over `target`: show what dropping here would do. The row lands in whichever
    /// section `target` belongs to, so dragging across the separator pins or unpins it.
    public func dragMoved(over target: String) {
        guard let dragged = draggingIdentifier, dragged != target else { return }

        // Resting on one row is how grouping is asked for; the dwell timer starts over whenever
        // the drag reaches a different row.
        if dwellTarget != target {
            dwellTarget = target
            clearGroupCandidate()
            startDwell(dragged: dragged, target: target)
        }
        guard groupCandidate == nil else { return }

        guard var pinnedOrder = previewPinned, var runningOrder = previewRunning else { return }

        let intoPinned: Bool
        let insertion: Int
        if let index = pinnedOrder.firstIndex(where: { $0.id == target }) {
            intoPinned = true
            insertion = index
        } else if let index = runningOrder.firstIndex(of: target) {
            intoPinned = false
            insertion = index
        } else {
            return
        }

        let moved = pinnedOrder.first { $0.id == dragged } ?? .application(dragged)
        pinnedOrder.removeAll { $0.id == dragged }
        runningOrder.removeAll { $0 == dragged }
        if intoPinned {
            pinnedOrder.insert(moved, at: min(insertion, pinnedOrder.count))
        } else {
            runningOrder.insert(dragged, at: min(insertion, runningOrder.count))
        }

        guard pinnedOrder != previewPinned || runningOrder != previewRunning else { return }
        previewPinned = pinnedOrder
        previewRunning = runningOrder
        rebuildRows()
    }

    private func startDwell(dragged: String, target: String) {
        dwellTask?.cancel()
        guard canGroup(dragged, with: target) else {
            dwellTask = nil
            return
        }
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: Self.groupDwell)
            guard !Task.isCancelled, let self, self.dwellTarget == target else { return }
            self.groupCandidate = target
            // The dragged row leaves the bar while it hovers: the rows stop sliding around and the
            // target grows a ring instead, which is what says "these are about to be one row".
            self.previewPinned = self.configuration.configuration.pinnedEntries
            self.previewRunning = self.runningIdentifiers
            self.rebuildRows()
        }
    }

    private func clearGroupCandidate() {
        dwellTask?.cancel()
        dwellTask = nil
        guard groupCandidate != nil else { return }
        groupCandidate = nil
        rebuildRows()
    }

    /// The drag ended. A cancelled drag — dropped outside, or on nothing — must leave the stored
    /// order exactly as it was.
    public func endDrag(commit: Bool) {
        let pinnedOrder = previewPinned
        let runningOrder = previewRunning
        let dragged = draggingIdentifier
        let candidate = groupCandidate
        dwellTask?.cancel()
        dwellTask = nil
        dwellTarget = nil
        draggingIdentifier = nil
        groupCandidate = nil
        previewPinned = nil
        previewRunning = nil

        // Resting on a row and letting go means "put these together", not "move me here".
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

    /// A row was dropped on `target`. The preview has normally already put it there; this covers
    /// a drop that arrived without one — a drag begun before the row list was ready.
    public func dropPinned(_ identifier: String, on target: String) {
        guard draggingIdentifier == nil else {
            dragMoved(over: target)
            return
        }
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
    public func nowPlayingChanged(_ playing: NowPlaying, isActive: Bool, players: [String] = []) {
        let wasShowing = showsNowPlayingRow
        nowPlaying = playing
        nowPlayingIsActive = isActive
        nowPlayingFallbackPlayer = players.first
        if showsNowPlayingRow != wasShowing { layoutDidChange?() }
        if !showsNowPlayingRow { hideNowPlaying?() }
    }

    public func togglePlayback() { mediaCommand?(.play) }
    public func nextTrack() { mediaCommand?(.next) }
    public func previousTrack() { mediaCommand?(.previous) }

    public func nowPlayingHoverChanged(_ hovering: Bool) {
        guard hovering else {
            scheduleFlyoutHide?()
            return
        }
        showNowPlaying?(nowPlaying)
    }

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

    /// Accepts a Finder drop of one or more `.app` bundles.
    @discardableResult
    public func pinApplications(at urls: [URL]) -> Bool {
        let identifiers = urls.compactMap { url -> String? in
            guard url.pathExtension == "app", let bundle = Bundle(url: url) else { return nil }
            return bundle.bundleIdentifier
        }
        guard !identifiers.isEmpty else { return false }
        for identifier in identifiers { pin(identifier) }
        return true
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
            refreshTrash()
        }
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
