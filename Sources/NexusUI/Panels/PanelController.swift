import AppKit
import NexusCore
import SwiftUI

/// The only code in Nexus that touches `NSWindow`. Panels are created once and reused, so the
/// hotkey path never pays a window-creation cost (design/mvp.md §2.3).
@MainActor
public final class PanelController {
    private let model: SidebarViewModel
    private let flyoutModel: WindowFlyoutViewModel
    private let groupModel: GroupPopoverViewModel
    private let folderModel: FolderStackViewModel
    private let permissions: any PermissionChecking
    private let configuration: ConfigurationController
    private let events: EventBus

    /// One bar per screen the display preference asks for — usually one, and one per monitor under
    /// `.everyDisplay` (D91). The first is the primary: the menu-bar display's bar, or the only one.
    private var bars: [NonActivatingPanel] = []
    private var edges: [EdgeTriggerPanel] = []
    /// Follows the pointer across monitors, installed only while the preference asks for it.
    private var pointerMonitor: Any?
    private var pointerScreen: DisplayIdentity?
    /// Whoever had the keyboard before the bar took it (M23).
    private var keyboardReturnsTo: NSRunningApplication?
    private var keyboardIdleTask: Task<Void, Never>?
    private var keyboardResignObserver: (any NSObjectProtocol)?

    private var sidebarPanel: NonActivatingPanel? { bars.first }
    private var flyoutPanel: NonActivatingPanel?
    private var flyoutHosting: NSView?
    private var flyoutHideTask: Task<Void, Never>?
    private var groupPanel: NonActivatingPanel?
    private var groupHosting: NSView?
    private var groupHideTask: Task<Void, Never>?
    /// Whoever had the keyboard before the group's name was clicked (D104).
    private var groupReturnsTo: NSRunningApplication?
    private var folderPanel: NonActivatingPanel?
    private var folderHosting: NSView?
    private var folderHideTask: Task<Void, Never>?
    /// Clicks elsewhere close the popovers. A non-activating panel never loses key status — it never
    /// had any — so nothing else would (D81).
    private var outsideClickMonitor: Any?
    private var hideTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var screenObserver: (any NSObjectProtocol)?

    /// Called whenever the bar's frame or edge changes, so Reserved Space (M12) can re-check what
    /// is underneath it.
    public var onBarFrameChange: (() -> Void)?

    /// Session-only: the status-item "Toggle Sidebar" hides the panel without changing settings.
    private var isSuppressed = false
    /// Auto-hide state. Always true when auto-hide is off.
    private var isRevealed = true

    public init(
        model: SidebarViewModel,
        flyoutModel: WindowFlyoutViewModel,
        groupModel: GroupPopoverViewModel,
        folderModel: FolderStackViewModel,
        permissions: any PermissionChecking,
        configuration: ConfigurationController,
        events: EventBus
    ) {
        self.model = model
        self.flyoutModel = flyoutModel
        self.groupModel = groupModel
        self.folderModel = folderModel
        self.permissions = permissions
        self.configuration = configuration
        self.events = events
    }

    // MARK: - Lifecycle

    public func start() {
        model.layoutDidChange = { [weak self] in self?.reframe(animated: false) }
        model.onHoverChange = { [weak self] hovering in self?.hoverChanged(hovering) }


        model.showWindows = { [weak self] identity in self?.showFlyout(for: identity) }
        model.scheduleFlyoutHide = { [weak self] in self?.scheduleFlyoutHide() }
        flyoutModel.onDismiss = { [weak self] in self?.hideFlyout() }
        flyoutModel.onContentChange = { [weak self] in self?.layoutFlyout() }
        let flyoutHostingView = FirstMouseHostingView(
            rootView: WindowFlyoutView(model: flyoutModel, permissions: permissions)
                .onHover { [weak self] hovering in self?.flyoutHoverChanged(hovering) }
        )
        flyoutHosting = flyoutHostingView
        flyoutPanel = NonActivatingPanel(
            contentView: flyoutHostingView,
            title: String(localized: "Nexus windows")
        )

        model.showGroup = { [weak self] group in self?.showGroup(group) }
        groupModel.onDismiss = { [weak self] in self?.hideGroup() }
        groupModel.setEditing = { [weak self] editing in self?.setGroupEditing(editing) }
        let groupHostingView = FirstMouseHostingView(
            rootView: GroupPopoverView(model: groupModel)
                .onHover { [weak self] hovering in self?.groupHoverChanged(hovering) }
        )
        groupHosting = groupHostingView
        groupPanel = NonActivatingPanel(
            contentView: groupHostingView,
            title: String(localized: "Nexus group")
        )

        model.setKeyboardFocus = { [weak self] focused in self?.setKeyboardFocus(focused) }
        model.showFolder = { [weak self] folder in self?.showFolder(folder) }
        model.scheduleFolderHide = { [weak self] in self?.scheduleFolderHide() }
        folderModel.onDismiss = { [weak self] in self?.hideFolder() }
        let folderHostingView = FirstMouseHostingView(
            rootView: FolderStackView(model: folderModel)
                .onHover { [weak self] hovering in self?.folderHoverChanged(hovering) }
        )
        folderHosting = folderHostingView
        folderPanel = NonActivatingPanel(
            contentView: folderHostingView,
            title: String(localized: "Nexus folder")
        )


        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.events.publish(.displaysChanged)
                self.reframe(animated: false)
            }
        }

        let stream = events.events()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if case .configurationChanged = event { self.applyBehavior() }
            }
        }

        isRevealed = !configuration.configuration.behavior.autoHide
        reframe(animated: false)
        for bar in bars { bar.orderFrontRegardless() }
        updateEdgePanel()
        updatePointerFollowing()
        Log.sidebar.notice("Sidebar panels shown: \(self.bars.count, privacy: .public)")
    }

    public func stop() {
        hideTask?.cancel()
        flyoutHideTask?.cancel()
        eventTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        groupHideTask?.cancel()
        folderHideTask?.cancel()
        keyboardIdleTask?.cancel()
        model.endKeyboardNavigation()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
        for bar in bars { bar.orderOut(nil) }
        for edge in edges { edge.orderOut(nil) }
        flyoutPanel?.orderOut(nil)
        groupPanel?.orderOut(nil)
        folderPanel?.orderOut(nil)
    }

    // MARK: - Dismissing the popovers

    /// A click outside closes whichever popover is open. Hover-out already does it after a grace
    /// period, but a click is a decision and should not wait 400 ms for the pointer to leave.
    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutside() }
        }
    }

    private func clickedOutside() {
        let point = NSEvent.mouseLocation
        // The bar itself is not "outside": clicking the media row is what opened this.
        if let sidebar = sidebarPanel, sidebar.frame.contains(point) { return }

        if groupModel.group != nil, groupPanel?.frame.contains(point) != true {
            groupModel.hide()
        }
        if folderModel.folder != nil, folderPanel?.frame.contains(point) != true {
            folderModel.hide()
        }
        removeOutsideClickMonitorIfIdle()
    }

    private func removeOutsideClickMonitorIfIdle() {
        guard groupModel.group == nil, folderModel.folder == nil else { return }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }


    // MARK: - Group popover

    private func showGroup(_ group: SidebarGroup) {
        groupHideTask?.cancel()
        hideFlyout()
        groupModel.show(group)
        layoutGroup()
        groupPanel?.orderFrontRegardless()
        installOutsideClickMonitor()
    }

    private func hideGroup() {
        groupHideTask?.cancel()
        groupHideTask = nil
        setGroupEditing(false)
        groupPanel?.orderOut(nil)
        removeOutsideClickMonitorIfIdle()
    }

    /// The popover takes the keyboard to be typed into, and only then (D104). It is the same
    /// bargain the bar's keyboard mode makes (D99): the user asked, explicitly, by clicking the
    /// name, and whoever had the keyboard gets it straight back.
    private func setGroupEditing(_ editing: Bool) {
        guard let panel = groupPanel else { return }
        guard editing else {
            guard panel.acceptsKeyboardFocus else { return }
            panel.acceptsKeyboardFocus = false
            if let application = groupReturnsTo,
               application.bundleIdentifier != Bundle.main.bundleIdentifier {
                application.activate()
            } else {
                NSApp.deactivate()
            }
            groupReturnsTo = nil
            return
        }
        groupHideTask?.cancel()
        groupHideTask = nil
        groupReturnsTo = NSApp.isActive ? nil : NSWorkspace.shared.frontmostApplication
        panel.acceptsKeyboardFocus = true
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func groupHoverChanged(_ hovering: Bool) {
        guard !hovering else {
            groupHideTask?.cancel()
            groupHideTask = nil
            return
        }
        scheduleGroupHide()
    }

    /// The same grace period the flyout gets: long enough to travel from the row to the popover.
    /// A name being typed holds the popover open however far away the pointer has wandered.
    private func scheduleGroupHide() {
        guard groupModel.group != nil, !groupModel.isRenaming else { return }
        groupHideTask?.cancel()
        groupHideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.groupModel.hide()
        }
    }

    // MARK: - Folder stack

    private func showFolder(_ folder: SidebarFolder) {
        folderHideTask?.cancel()
        hideFlyout()
        groupModel.hide()
        folderModel.show(folder)
        layoutFolder()
        folderPanel?.orderFrontRegardless()
        installOutsideClickMonitor()
    }

    private func hideFolder() {
        folderHideTask?.cancel()
        folderHideTask = nil
        folderPanel?.orderOut(nil)
        removeOutsideClickMonitorIfIdle()
    }

    private func folderHoverChanged(_ hovering: Bool) {
        guard !hovering else {
            folderHideTask?.cancel()
            folderHideTask = nil
            return
        }
        scheduleFolderHide()
    }

    /// The grace period between the folder's row and its stack — the same one the flyout gets, and
    /// what makes a stack opened by hovering (F2) survive the trip from the row to the popover.
    private func scheduleFolderHide() {
        guard folderModel.folder != nil else { return }
        folderHideTask?.cancel()
        folderHideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.folderModel.hide()
        }
    }

    private func layoutFolder() {
        guard let panel = folderPanel,
              let hosting = folderHosting,
              let (sidebar, screen) = barUnderPointer(),
              let folder = folderModel.folder
        else { return }

        hosting.layoutSubtreeIfNeeded()
        let margin = SidebarLayout.screenMargin * 2
        let fitting = hosting.fittingSize
        let size = CGSize(
            width: min(fitting.width, screen.visibleFrame.width - margin),
            height: min(fitting.height, screen.visibleFrame.height - margin)
        )
        panel.setFrame(
            SidebarLayout.flyoutFrame(
                size: size,
                beside: sidebar.frame,
                anchor: anchorOffset(forRow: folder.id),
                in: screen.visibleFrame,
                position: model.appearance.position
            ),
            display: true
        )
    }

    /// The popover follows its group: an edit that renames it, empties it or dissolves it has to
    /// be reflected before the next frame, or the panel shows a dock that no longer exists.
    public func groupsChanged() {
        folderModel.update(from: model.pinned)
        if folderModel.folder != nil { layoutFolder() }
        groupModel.update(from: model.pinned)
        guard groupModel.group != nil else { return }
        layoutGroup()
    }

    private func layoutGroup() {
        guard let panel = groupPanel,
              let hosting = groupHosting,
              let (sidebar, screen) = barUnderPointer(),
              let group = groupModel.group
        else { return }

        hosting.layoutSubtreeIfNeeded()
        let margin = SidebarLayout.screenMargin * 2
        let fitting = hosting.fittingSize
        let size = CGSize(
            width: min(fitting.width, screen.visibleFrame.width - margin),
            height: min(fitting.height, screen.visibleFrame.height - margin)
        )
        panel.setFrame(
            SidebarLayout.flyoutFrame(
                size: size,
                beside: sidebar.frame,
                anchor: anchorOffset(forRow: group.id),
                in: screen.visibleFrame,
                position: model.appearance.position
            ),
            display: true
        )
    }

    // MARK: - Window flyout

    private func showFlyout(for identity: ApplicationIdentity) {
        guard let item = (model.pinnedItems + model.running).first(where: { $0.identity == identity })
        else { return }
        flyoutHideTask?.cancel()
        flyoutModel.isVertical = model.appearance.position.isVertical
        flyoutModel.show(identity, name: item.name)
        layoutFlyout()
        flyoutPanel?.orderFrontRegardless()
    }

    private func hideFlyout() {
        flyoutHideTask?.cancel()
        flyoutHideTask = nil
        flyoutPanel?.orderOut(nil)
        model.flyoutClosed()
    }

    private func flyoutHoverChanged(_ hovering: Bool) {
        guard !hovering else {
            flyoutHideTask?.cancel()
            flyoutHideTask = nil
            return
        }
        scheduleFlyoutHide()
    }

    /// The pointer left the flyout or the row that opened it. The grace period is what lets it
    /// travel from one to the other without the flyout vanishing on the way.
    private func scheduleFlyoutHide() {
        guard flyoutModel.target != nil else { return }
        flyoutHideTask?.cancel()
        flyoutHideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flyoutModel.hide()
        }
    }

    /// The flyout's height depends on its content (window count, previews that finish loading,
    /// the permission screen), so it is measured rather than computed.
    private func layoutFlyout() {
        guard let panel = flyoutPanel,
              let hosting = flyoutHosting,
              let (sidebar, screen) = barUnderPointer(),
              let identity = flyoutModel.target
        else { return }

        hosting.layoutSubtreeIfNeeded()
        let margin = SidebarLayout.screenMargin * 2
        let fitting = hosting.fittingSize
        let size = CGSize(
            width: min(fitting.width, screen.visibleFrame.width - margin),
            height: min(
                max(fitting.height, WindowFlyoutView.rowHeight),
                screen.visibleFrame.height - margin
            )
        )
        panel.setFrame(
            SidebarLayout.flyoutFrame(
                size: size,
                beside: sidebar.frame,
                anchor: anchorOffset(forRow: identity.bundleIdentifier),
                in: screen.visibleFrame,
                position: model.appearance.position
            ),
            display: true
        )
    }

    /// Where the palette should sit to look like it came out of the Search row (M19). `nil` when
    /// there is no visible bar to anchor to — the bar is suppressed, hidden by auto-hide, or has no
    /// Search row — and the palette falls back to the middle of the screen.
    public func searchRowAnchor() -> SidebarLayout.BarAnchor? {
        guard let (panel, screen) = barUnderPointer(),
              !isSuppressed, isRevealed,
              let section = model.searchSectionIndex
        else { return nil }
        return SidebarLayout.BarAnchor(
            bar: panel.frame,
            screen: screen.visibleFrame,
            rowCentre: SidebarLayout.rowCentre(
                sectionRowCounts: model.sectionRowCounts,
                section: section,
                row: 0,
                appearance: model.appearance
            ),
            position: model.appearance.position
        )
    }

    /// The bar the pointer is on, and its screen — which is the bar a flyout or a popover belongs
    /// to. With one bar this is always that bar; with a bar per display (D91) it is the one that was
    /// actually clicked, so a window list does not open on the other monitor.
    private func barUnderPointer() -> (NonActivatingPanel, NSScreen)? {
        let screens = targetScreens
        let pairs = Array(zip(bars, screens))
        guard !pairs.isEmpty else { return nil }
        let pointer = NSEvent.mouseLocation
        return pairs.first { $0.0.frame.contains(pointer) }
            ?? pairs.first { $0.1.frame.contains(pointer) }
            ?? pairs.first
    }

    /// Distance to the centre of the row that *draws* `id` — which for an application inside a
    /// group is the group's row, not one of its own.
    private func anchorOffset(forRow id: String) -> CGFloat {
        let counts = model.sectionRowCounts
        if let row = model.pinned.firstIndex(where: { row in
            row.id == id || row.group?.items.contains { $0.id == id } == true
        }) {
            return SidebarLayout.rowCentre(
                sectionRowCounts: counts,
                section: model.pinnedSectionIndex,
                row: row,
                appearance: model.appearance
            )
        }
        if let row = model.running.firstIndex(where: { $0.id == id }) {
            return SidebarLayout.rowCentre(
                sectionRowCounts: counts,
                section: model.runningSectionIndex,
                row: row,
                appearance: model.appearance
            )
        }
        guard let panel = sidebarPanel else { return 0 }
        return (model.appearance.position.isVertical ? panel.frame.height : panel.frame.width) / 2
    }

    // MARK: - Keyboard navigation (M23)

    /// The shortcut asked for the bar. Takes the keyboard, or gives it back if the bar already has
    /// it — the same toggle the palette's shortcut is.
    public func focusBar() {
        guard !isSuppressed, let panel = sidebarPanel else { return }
        if model.isKeyboardNavigating {
            model.endKeyboardNavigation()
            return
        }
        if !isRevealed { reveal() }
        keyboardReturnsTo = NSApp.isActive ? nil : NSWorkspace.shared.frontmostApplication
        panel.acceptsKeyboardFocus = true
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        model.beginKeyboardNavigation()
        armKeyboardIdleTimeout()
        // Clicking into anything else takes the keyboard back, and the ring has to go with it.
        keyboardResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.endKeyboardNavigation() }
        }
    }

    /// One key press while the bar has the keyboard. `false` lets the key travel on, which is what
    /// keeps every other key — a typed character, a system shortcut — working normally.
    private func handleKey(_ command: BarKeyCommand) -> Bool {
        guard model.isKeyboardNavigating else { return false }
        armKeyboardIdleTimeout()
        switch command {
        case .previous: model.moveFocus(by: -1)
        case .next: model.moveFocus(by: 1)
        case .first: model.focusFirstRow()
        case .last: model.focusLastRow()
        case .activate: model.activateFocusedRow()
        case .cancel: model.endKeyboardNavigation()
        }
        return true
    }

    /// Hands the keyboard back: to whoever had it, or to nobody.
    private func setKeyboardFocus(_ focused: Bool) {
        keyboardIdleTask?.cancel()
        keyboardIdleTask = nil
        guard let panel = sidebarPanel else { return }
        if focused {
            armKeyboardIdleTimeout()
            return
        }
        if let keyboardResignObserver {
            NotificationCenter.default.removeObserver(keyboardResignObserver)
        }
        keyboardResignObserver = nil
        panel.acceptsKeyboardFocus = false
        if let application = keyboardReturnsTo,
           application.bundleIdentifier != Bundle.main.bundleIdentifier {
            application.activate()
        } else {
            NSApp.deactivate()
        }
        keyboardReturnsTo = nil
    }

    /// Insurance, not a feature: a bar left holding the keyboard because something went wrong is
    /// a machine that will not type. Any key press restarts the clock.
    private func armKeyboardIdleTimeout() {
        keyboardIdleTask?.cancel()
        keyboardIdleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.model.endKeyboardNavigation()
        }
    }

    /// Whether the bar is on screen at all — what the menu item's own title reports.
    public var isBarVisible: Bool { !isSuppressed }

    public func toggleSidebar() {
        isSuppressed.toggle()
        if isSuppressed {
            for bar in bars { bar.orderOut(nil) }
            for edge in edges { edge.orderOut(nil) }
            onBarFrameChange?()
        } else {
            reframe(animated: false)
            for bar in bars { bar.orderFrontRegardless() }
            updateEdgePanel()
        }
    }

    // MARK: - Geometry

    /// Target screen for the sidebar, honouring the stored display preference (D11).
    private var targetScreen: NSScreen? { targetScreens.first }

    /// Every screen that should carry a bar: one, or all of them under `.everyDisplay` (D91).
    private var targetScreens: [NSScreen] {
        DisplayService.screens(for: configuration.configuration.appearance.display)
    }

    /// Creates and destroys panels so there is exactly one bar per target screen. Panels are reused
    /// across reframes — the hotkey path must never pay for window creation (`design/mvp.md` §2.3)
    /// — so this only runs when a display arrives or leaves.
    private func syncPanels(to screens: [NSScreen]) {
        while bars.count > screens.count {
            bars.removeLast().orderOut(nil)
            if edges.count > screens.count { edges.removeLast().orderOut(nil) }
        }
        while bars.count < screens.count {
            let hosting = BarHostingView(rootView: SidebarView(model: model))
            hosting.onFiles = { [weak self] urls in self?.model.pinApplications(at: urls) ?? false }
            let bar = NonActivatingPanel(
                contentView: hosting,
                title: String(localized: "Nexus")
            )
            bar.onKey = { [weak self] command in self?.handleKey(command) ?? false }
            bars.append(bar)
            if !isSuppressed { bar.orderFrontRegardless() }
        }
        while edges.count < screens.count {
            edges.append(EdgeTriggerPanel { [weak self] in self?.reveal() })
        }
    }

    public func reframe(animated: Bool) {
        let screens = targetScreens
        syncPanels(to: screens)
        guard !screens.isEmpty, !isSuppressed else { return }
        let appearance = model.appearance
        // The bar's zones depend on how much screen there is along its own axis (M14), which only
        // this knows. With a bar on every display it is the *smallest* of them: one row budget is
        // shared by every bar, and a budget that fits the widest screen would overflow the others.
        let extents = screens.map { screen -> CGFloat in
            let visible = screen.visibleFrame
            return (appearance.position.isVertical ? visible.height : visible.width)
                - SidebarLayout.screenMargin * 2
        }
        model.availableExtent = extents.min() ?? 0
        let size = SidebarLayout.size(
            zones: model.zones,
            appearance: appearance,
            expanded: model.isExpanded
        )
        for (index, screen) in screens.enumerated() where index < bars.count {
            let frame = SidebarLayout.frame(
                size: size,
                in: screen.visibleFrame,
                position: appearance.position,
                hidden: !isRevealed
            )
            setFrame(frame, on: bars[index], animated: animated)
        }
        updateEdgePanel()
        onBarFrameChange?()
        if groupModel.group != nil { layoutGroup() }
        if folderModel.folder != nil { layoutFolder() }
    }

    /// What Reserved Space needs to know: where each bar is, and on which screen. Empty whenever
    /// the bars are not really there — suppressed, hidden, or auto-hiding, which reserves nothing.
    /// One entry per display carrying a bar (D91), so a window is pushed off the bar it is actually
    /// under rather than off a bar on another monitor.
    public var reservedSpaceGeometries: [ReservedSpaceController.Geometry] {
        guard !isSuppressed, isRevealed, !configuration.configuration.behavior.autoHide
        else { return [] }
        // The screen is taken from where each bar *is*, not from the preference's order: those two
        // disagree for a frame or two whenever a bar is moving between displays, and a bar paired
        // with the wrong screen tells Reserved Space that every window on that screen is in the
        // way — which pushes windows onto the other monitor (D91).
        return bars.compactMap { bar in
            guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(bar.frame) })
            else { return nil }
            return ReservedSpaceController.Geometry(
                bar: bar.frame,
                visible: screen.visibleFrame,
                display: screen.frame,
                position: model.appearance.position
            )
        }
    }

    private func setFrame(_ frame: NSRect, on panel: NSPanel, animated: Bool) {
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func updateEdgePanel() {
        let autoHide = configuration.configuration.behavior.autoHide
        guard autoHide, !isSuppressed else {
            for edge in edges { edge.orderOut(nil) }
            return
        }
        // A trigger strip per bar: the edge of the display you are on is the one that should
        // reveal, and revealing shows every bar, because they are one bar in three places.
        for (index, screen) in targetScreens.enumerated() where index < edges.count {
            edges[index].setFrame(
                SidebarLayout.edgeTriggerFrame(
                    in: screen.visibleFrame,
                    position: model.appearance.position
                ),
                display: false
            )
            edges[index].orderFrontRegardless()
        }
    }

    // MARK: - Following the pointer

    /// `.withMouse` used to mean "whichever display the pointer was on the last time something else
    /// caused a reframe", which is not what it says. A global mouse-moved monitor is the only way
    /// macOS offers to know the pointer crossed monitors — there is no notification for it — and it
    /// is installed *only* in this mode, does nothing but compare two display identities, and
    /// reframes on a change (D91).
    private func updatePointerFollowing() {
        let follows = configuration.configuration.appearance.display == .withMouse
        guard follows else {
            if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
            pointerMonitor = nil
            pointerScreen = nil
            return
        }
        guard pointerMonitor == nil else { return }
        pointerScreen = DisplayService.screenContainingMouse().flatMap(DisplayService.identity(of:))
        Log.sidebar.notice("Following the pointer across displays")
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
    }

    private func pointerMoved() {
        guard let screen = DisplayService.screenContainingMouse(),
              let identity = DisplayService.identity(of: screen),
              identity != pointerScreen
        else { return }
        pointerScreen = identity
        Log.sidebar.notice("Pointer moved to another display; the bar follows")
        reframe(animated: true)
    }

    // MARK: - Auto-hide

    private func applyBehavior() {
        updatePointerFollowing()
        let autoHide = configuration.configuration.behavior.autoHide
        if !autoHide, !isRevealed { reveal() }
        if autoHide, isRevealed { scheduleHide() }
        reframe(animated: false)
    }

    private func hoverChanged(_ hovering: Bool) {
        if hovering {
            hideTask?.cancel()
            hideTask = nil
            reveal()
        } else {
            scheduleHide()
        }
    }

    private func reveal() {
        hideTask?.cancel()
        hideTask = nil
        guard !isRevealed else { return }
        isRevealed = true
        reframe(animated: true)
        for bar in bars { bar.orderFrontRegardless() }
    }

    private func scheduleHide() {
        guard configuration.configuration.behavior.autoHide, isRevealed else { return }
        let delay = configuration.configuration.behavior.autoHideDelay
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.isRevealed else { return }
            self.isRevealed = false
            self.model.setExpanded(false)
            self.reframe(animated: true)
        }
    }
}
