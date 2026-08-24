import AppKit
import CoreGraphics
import NexusCore
import SwiftUI

/// Data, filter, sort, grouping, selection and keyboard focus for the window switcher (M25). The
/// panel and grid views are later tasks; this is the object they read from and act through.
@MainActor
@Observable
public final class SwitcherViewModel {
    public enum Direction: Sendable { case left, right, up, down }

    public private(set) var windows: [NexusWindow] = []
    public private(set) var previews: [CGWindowID: NSImage] = [:]
    public private(set) var accessibility: PermissionStatus = .denied
    public private(set) var previewsOfferDismissed = false
    public private(set) var selection: Set<String> = []
    public private(set) var focused: String?

    public var query = "" { didSet { rebuild() } }
    public var grouping: WindowSwitcherGrouping { didSet { persist(); rebuild() } }
    public var sort: WindowSwitcherSort { didSet { persist(); rebuild() } }
    public var isReversed: Bool { didSet { persist(); rebuild() } }
    public private(set) var sections: [SwitcherSection] = []
    /// How many cards are across, published by the view so arrow-key focus moves by a real row
    /// (Task 6, and `moveFocus`'s `columns` parameter).
    public var columns = 1
    /// `bundleIdentifier` → resolved application URL. See `applicationURL(forBundleIdentifier:)`.
    @ObservationIgnored private var applicationURLCache: [String: URL] = [:]

    @ObservationIgnored private let service: any WindowServing
    @ObservationIgnored private let previewService: any WindowPreviewing
    // Not `private`: Task 5's gate view reads this through the view model rather than being handed
    // a second reference to the permission service, and an `internal` (default) property is the
    // one access level an extension added in another file of this module can still see.
    @ObservationIgnored let permissions: any PermissionChecking
    @ObservationIgnored private let events: EventBus
    @ObservationIgnored private let configuration: ConfigurationController
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    /// Bundle identifiers, most recently activated first. Seeded from the frecency store the
    /// palette already keeps, so the very first open is not in arbitrary order (§4).
    @ObservationIgnored private var activationOrder: [String] = []
    /// Which screen a window is on, as a name, so the view model never touches `NSScreen` in a
    /// test. Replaced in tests; the default asks the real screens.
    @ObservationIgnored public var displayName: @MainActor (CGRect) -> String = SwitcherViewModel.screenName

    @ObservationIgnored public var onClose: (() -> Void)?

    public init(
        service: any WindowServing,
        previewService: any WindowPreviewing,
        permissions: any PermissionChecking,
        events: EventBus,
        configuration: ConfigurationController
    ) {
        self.service = service
        self.previewService = previewService
        self.permissions = permissions
        self.events = events
        self.configuration = configuration
        let behavior = configuration.configuration.behavior
        grouping = behavior.windowSwitcherGrouping
        sort = behavior.windowSwitcherSort
        isReversed = behavior.windowSwitcherSortReversed
        accessibility = permissions.status(of: .accessibility)
        activationOrder = Frecency(entries: configuration.configuration.frecency)
            .recents(limit: 32)
            .compactMap { $0.hasPrefix("app:") ? String($0.dropFirst(4)) : nil }
    }

    // MARK: - Lifecycle

    public func start() {
        // Subscribe synchronously: creating the stream inside the Task would drop any event
        // published between `start()` and the Task's first run.
        let stream = events.events()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .applicationActivated(let identity):
                    self.noteActivation(identity)
                case .windowsChanged, .applicationTerminated, .applicationLaunched:
                    await self.reload()
                case .permissionChanged(.accessibility, let status):
                    self.accessibility = status
                    await self.reload()
                default:
                    continue
                }
            }
        }
    }

    public func stop() {
        eventTask?.cancel()
        eventTask = nil
        previewTask?.cancel()
        previewTask = nil
    }

    /// Called by the panel just before it goes on screen: the grid shows the cached snapshot at
    /// once and the fresh enumeration replaces it a moment later. An empty grid for 200 ms is
    /// worse than a stale one (spec §3).
    public func prepareForDisplay() {
        query = ""
        selection = []
        accessibility = permissions.status(of: .accessibility)
        rebuild()
        Task { await reload() }
    }

    public func reload() async {
        accessibility = permissions.status(of: .accessibility)
        guard accessibility == .granted else {
            windows = []
            rebuild()
            return
        }
        windows = (try? await service.allWindows()) ?? []
        rebuild()
        requestPreviews()
    }

    // MARK: - Gates

    public var showsAccessibilityGate: Bool { accessibility != .granted }

    public var showsPreviewsOffer: Bool {
        accessibility == .granted
            && configuration.configuration.behavior.windowSwitcherThumbnails
            && !previewsOfferDismissed
            && permissions.status(of: .screenRecording) != .granted
            && !windows.isEmpty
    }

    public func dismissPreviewsOffer() { previewsOfferDismissed = true }

    public func requestAccessibility() { permissions.requestOrOpenSettings(.accessibility) }

    public func requestScreenRecording() { permissions.requestOrOpenSettings(.screenRecording) }

    // MARK: - Icons

    /// Memoized so a card's body — read twice per evaluation, on every hover, scroll and
    /// selection change — pays the LaunchServices round trip at most once per application.
    public func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        if let cached = applicationURLCache[bundleIdentifier] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        if let url { applicationURLCache[bundleIdentifier] = url }
        return url
    }

    // MARK: - Recency

    public func noteActivation(_ identity: ApplicationIdentity) {
        activationOrder.removeAll { $0 == identity.bundleIdentifier }
        activationOrder.insert(identity.bundleIdentifier, at: 0)
        rebuild()
    }

    // MARK: - Building the grid

    private func rebuild() {
        let matched = windows.filter { matches($0) }
        let ordered = ordered(matched)
        switch grouping {
        case .flat:
            sections = ordered.isEmpty ? [] : [SwitcherSection(id: "all", title: "", windows: ordered)]
        case .application:
            sections = grouped(ordered, by: { $0.identity.owner.bundleIdentifier }, title: { $0.applicationName })
        case .display:
            sections = grouped(ordered, by: { displayName($0.frame) }, title: { displayName($0.frame) })
        }
        if let focused, sections.flatMap(\.windows).contains(where: { $0.id == focused }) == false {
            self.focused = nil
        }
    }

    private func matches(_ window: NexusWindow) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        // Every word has to land somewhere, so `saf goo` finds Safari's Google window while
        // `saf zzz` finds nothing.
        return StringMatch.words(in: query).allSatisfy { word in
            StringMatch.match(query: word, candidate: window.applicationName) != nil
                || StringMatch.match(query: word, candidate: window.title) != nil
        }
    }

    private func ordered(_ windows: [NexusWindow]) -> [NexusWindow] {
        let sorted: [NexusWindow] = switch sort {
        case .title:
            windows.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .application:
            windows.sorted {
                let left = $0.applicationName.localizedStandardCompare($1.applicationName)
                return left == .orderedSame ? $0.identity.number < $1.identity.number : left == .orderedAscending
            }
        case .recent:
            // Within one application, AX order is front-to-back and is left alone: the offset
            // tiebreak only fires between windows of *different* applications that tied on rank
            // (neither has been activated), and there it goes to the bundle identifier rather
            // than to `windows`'s own order — enumeration order is `allWindows()`'s to define,
            // not something this view model may depend on being stable.
            windows.enumerated().sorted { left, right in
                let a = rank(left.element)
                let b = rank(right.element)
                guard a == b else { return a < b }
                let leftBundle = left.element.identity.owner.bundleIdentifier
                let rightBundle = right.element.identity.owner.bundleIdentifier
                return leftBundle == rightBundle ? left.offset < right.offset : leftBundle < rightBundle
            }.map(\.element)
        }
        return isReversed ? sorted.reversed() : sorted
    }

    private func rank(_ window: NexusWindow) -> Int {
        activationOrder.firstIndex(of: window.identity.owner.bundleIdentifier) ?? Int.max
    }

    private func grouped(
        _ windows: [NexusWindow],
        by key: (NexusWindow) -> String,
        title: (NexusWindow) -> String
    ) -> [SwitcherSection] {
        var order: [String] = []
        var byKey: [String: [NexusWindow]] = [:]
        var titles: [String: String] = [:]
        for window in windows {
            let id = key(window)
            if byKey[id] == nil {
                order.append(id)
                titles[id] = title(window)
            }
            byKey[id, default: []].append(window)
        }
        return order.map { SwitcherSection(id: $0, title: titles[$0] ?? $0, windows: byKey[$0] ?? []) }
    }

    private static func screenName(_ frame: CGRect) -> String {
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
            ?? NSScreen.screens.first { $0.frame.intersects(frame) }
        return screen?.localizedName ?? String(localized: "Other display")
    }

    // MARK: - Actions

    public func activate(_ window: NexusWindow) {
        Task { [service] in try? await service.activate(window.identity) }
        onClose?()
    }

    public func close(_ window: NexusWindow) async {
        // The card stays until `windowsChanged` says otherwise: a document with unsaved work
        // puts up a sheet and the window is still there (spec §6).
        try? await service.close(window.identity)
    }

    public func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    public var canAddStack: Bool { !selection.isEmpty }

    /// The selection is windows; a stack is applications. Window identity does not survive a
    /// relaunch, so a stack of windows would empty itself overnight (spec §7).
    public func stackFromSelection() -> ApplicationGroup? {
        let selected = windows.filter { selection.contains($0.id) }
        var distinct: [String] = []
        var names: [String] = []
        for window in selected {
            let bundle = window.identity.owner.bundleIdentifier
            guard !distinct.contains(bundle) else { continue }
            distinct.append(bundle)
            names.append(window.applicationName)
        }
        guard !distinct.isEmpty else { return nil }
        // ponytail: the switcher holds no application service, so unlike a stack made in the bar
        // this can't consult LSApplicationCategoryType for a shared-category name — it always
        // falls through to `ApplicationCategory`'s own name-based fallback. Upgrade this if the
        // switcher ever gains an `ApplicationServing` dependency for another reason.
        let name = ApplicationCategory.groupName(for: Array(repeating: nil, count: distinct.count), names: names)
        return ApplicationGroup(name: name, applications: distinct)
    }

    public func addStack() {
        guard let group = stackFromSelection() else { return }
        configuration.update { $0.pinnedEntries.append(.group(group)) }
        selection = []
    }

    // MARK: - Keyboard

    public func focusFirst() {
        focused = sections.first?.windows.first?.id
    }

    public func clearQueryOrClose() {
        if query.isEmpty { onClose?() } else { query = "" }
    }

    public func activateFocused() {
        guard let focused, let window = sections.flatMap(\.windows).first(where: { $0.id == focused })
        else { return }
        activate(window)
    }

    public func closeFocused() async {
        guard let focused, let window = sections.flatMap(\.windows).first(where: { $0.id == focused })
        else { return }
        await close(window)
    }

    /// Moves within one row for left and right — wrapping at its ends rather than spilling into
    /// the next row, which is what makes a grid feel like a grid — and by a whole row for up and
    /// down.
    public func moveFocus(_ direction: Direction, columns: Int) {
        let all = sections.flatMap(\.windows)
        guard !all.isEmpty else { return }
        let columns = max(1, columns)
        guard let focused, let index = all.firstIndex(where: { $0.id == focused }) else {
            self.focused = all.first?.id
            return
        }
        let row = index / columns
        let column = index % columns
        let rowStart = row * columns
        let rowCount = min(columns, all.count - rowStart)
        let next: Int = switch direction {
        case .left: rowStart + (column - 1 + rowCount) % rowCount
        case .right: rowStart + (column + 1) % rowCount
        case .up: max(0, index - columns)
        case .down: min(all.count - 1, index + columns)
        }
        self.focused = all[next].id
    }

    // MARK: - Previews

    private func requestPreviews() {
        guard configuration.configuration.behavior.windowSwitcherThumbnails,
              permissions.status(of: .screenRecording) == .granted
        else { return }
        let identities = windows.map(\.identity)
        previewTask?.cancel()
        previewTask = Task { [previewService] in
            for await (identity, image) in await previewService.previews(for: identities, maxDimension: 480) {
                guard !Task.isCancelled else { return }
                previews[identity.number] = NSImage(
                    cgImage: image.image,
                    size: NSSize(width: image.image.width, height: image.image.height)
                )
            }
        }
    }

    private func persist() {
        configuration.update {
            $0.behavior.windowSwitcherGrouping = grouping
            $0.behavior.windowSwitcherSort = sort
            $0.behavior.windowSwitcherSortReversed = isReversed
        }
    }
}
