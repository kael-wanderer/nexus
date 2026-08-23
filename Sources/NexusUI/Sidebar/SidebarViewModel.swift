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

/// Views own no system logic (§62): the view binds to this, this talks to service protocols.
@MainActor
@Observable
public final class SidebarViewModel {
    public private(set) var pinned: [SidebarItem] = []
    public private(set) var running: [SidebarItem] = []

    /// Read straight through to the single source of truth. `ConfigurationController` is
    /// `@Observable`, so SwiftUI still re-renders when these change.
    public var appearance: AppearanceConfiguration { configuration.configuration.appearance }
    public var behavior: BehaviorConfiguration { configuration.configuration.behavior }

    /// Hover-expanded (names visible). Never true when `behavior.hoverExpand` is off.
    public var isExpanded = false

    /// Drives which Trash icon the utility row draws.
    public private(set) var trashIsEmpty = TrashService.isEmpty

    /// The row currently being dragged, so it can be drawn as a gap (D59).
    public private(set) var draggingIdentifier: String?
    /// Where the rows would land if the drag were dropped now — one list per section. Never
    /// written to the configuration until the drop lands.
    private var previewPinned: [String]?
    private var previewRunning: [String]?

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
        var counts = [pinned.count]
        if behavior.showRunningApplications { counts.append(running.count) }
        counts.append(openSearch == nil ? 1 : 2)
        return counts
    }

    public var showsPlaceholder: Bool {
        pinned.isEmpty && (running.isEmpty || !behavior.showRunningApplications)
    }

    public func refresh() async {
        let identifiers = pinnedIdentifiers
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

    /// The identifiers the pinned section shows: the stored order, or the drag preview while one
    /// is in flight. A running application being dragged into the section appears here before it
    /// is pinned, which is what lets the rows move under the drag (D59).
    private var pinnedIdentifiers: [String] {
        previewPinned ?? configuration.configuration.pinnedApplications
    }

    /// The running section's order: the applications the user has dragged, in the order they put
    /// them, then everything else alphabetically. An application nobody has moved keeps its
    /// alphabetical place, so the section does not shuffle itself around.
    private var runningIdentifiers: [String] {
        if let previewRunning { return previewRunning }
        let stored = configuration.configuration.runningApplicationOrder
        let pinnedSet = Set(configuration.configuration.pinnedApplications)
        let known = Set(alphabeticalRunning)
        let moved = stored.filter { known.contains($0) && !pinnedSet.contains($0) }
        let rest = alphabeticalRunning.filter { !moved.contains($0) && !pinnedSet.contains($0) }
        return moved + rest
    }

    /// Composes the two row lists from the resolved items. Synchronous on purpose: a drag has to
    /// reorder the rows in the same run loop turn as the pointer moves.
    private func rebuildRows() {
        let identifiers = pinnedIdentifiers
        let pinnedSet = Set(identifiers)
        var resolvedPinned: [SidebarItem] = []
        for identifier in identifiers {
            guard var item = items[identifier] else { continue }
            item.isPinned = true
            resolvedPinned.append(item)
        }
        let resolvedRunning = runningIdentifiers
            .filter { !pinnedSet.contains($0) }
            .compactMap { items[$0] }

        let layoutChanged = resolvedPinned.count != pinned.count || resolvedRunning.count != running.count
        pinned = resolvedPinned
        running = resolvedRunning
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
        configuration.update { $0.pinnedApplications.append(identifier) }
        Log.sidebar.notice("Pinned \(identifier, privacy: .public)")
    }

    public func unpin(_ identifier: String) {
        configuration.update { $0.pinnedApplications.removeAll { $0 == identifier } }
        Log.sidebar.notice("Unpinned \(identifier, privacy: .public)")
    }

    /// Moves `identifier` so it sits immediately before `target`. Both must already be pinned;
    /// anything else (a Finder drag arriving as a string, say) is ignored.
    public func movePinned(_ identifier: String, before target: String) {
        var order = configuration.configuration.pinnedApplications
        guard identifier != target,
              let from = order.firstIndex(of: identifier),
              order.contains(target)
        else { return }
        order.remove(at: from)
        guard let insertion = order.firstIndex(of: target) else { return }
        order.insert(identifier, at: insertion)
        configuration.update { $0.pinnedApplications = order }
    }

    // MARK: - Dragging

    /// A row started moving — pinned or running. A running application is previewed inside the
    /// pinned section as soon as the drag reaches it, and dropping is what pins it there.
    public func beginDrag(_ identifier: String) {
        guard items[identifier] != nil else { return }
        draggingIdentifier = identifier
        previewPinned = pinnedIdentifiers
        previewRunning = runningIdentifiers
    }

    /// The drag is over `target`: show what dropping here would do. The row lands in whichever
    /// section `target` belongs to, so dragging across the separator pins or unpins it.
    public func dragMoved(over target: String) {
        guard let dragged = draggingIdentifier,
              dragged != target,
              var pinnedOrder = previewPinned,
              var runningOrder = previewRunning
        else { return }

        let intoPinned: Bool
        let insertion: Int
        if let index = pinnedOrder.firstIndex(of: target) {
            intoPinned = true
            insertion = index
        } else if let index = runningOrder.firstIndex(of: target) {
            intoPinned = false
            insertion = index
        } else {
            return
        }

        pinnedOrder.removeAll { $0 == dragged }
        runningOrder.removeAll { $0 == dragged }
        let clamped = min(insertion, intoPinned ? pinnedOrder.count : runningOrder.count)
        if intoPinned {
            pinnedOrder.insert(dragged, at: clamped)
        } else {
            runningOrder.insert(dragged, at: clamped)
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
        draggingIdentifier = nil
        previewPinned = nil
        previewRunning = nil
        guard commit, let pinnedOrder, let runningOrder else {
            rebuildRows()
            return
        }
        let stored = configuration.configuration
        guard pinnedOrder != stored.pinnedApplications || runningOrder != runningIdentifiers else {
            rebuildRows()
            return
        }
        configuration.update {
            $0.pinnedApplications = pinnedOrder
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
        let order = configuration.configuration.pinnedApplications
        guard identifier != target, order.contains(target), !order.contains(identifier) else { return }
        pin(identifier)
        movePinned(identifier, before: target)
    }

    /// Reorder by one slot; the same operation the context menu offers.
    public func canMovePinned(_ identifier: String, by delta: Int) -> Bool {
        let order = configuration.configuration.pinnedApplications
        guard let index = order.firstIndex(of: identifier) else { return false }
        return order.indices.contains(index + delta)
    }

    public func movePinned(_ identifier: String, by delta: Int) {
        var order = configuration.configuration.pinnedApplications
        guard let index = order.firstIndex(of: identifier),
              order.indices.contains(index + delta)
        else { return }
        order.remove(at: index)
        order.insert(identifier, at: index + delta)
        configuration.update { $0.pinnedApplications = order }
    }

    public func movePinnedToEnd(_ identifier: String) {
        var order = configuration.configuration.pinnedApplications
        guard let from = order.firstIndex(of: identifier) else { return }
        order.remove(at: from)
        order.append(identifier)
        configuration.update { $0.pinnedApplications = order }
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
