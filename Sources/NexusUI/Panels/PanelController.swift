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
    private let nowPlayingModel: NowPlayingPopoverViewModel
    private let permissions: any PermissionChecking
    private let configuration: ConfigurationController
    private let events: EventBus

    private var sidebarPanel: NonActivatingPanel?
    private var edgePanel: EdgeTriggerPanel?
    private var flyoutPanel: NonActivatingPanel?
    private var flyoutHosting: NSView?
    private var flyoutHideTask: Task<Void, Never>?
    private var groupPanel: NonActivatingPanel?
    private var groupHosting: NSView?
    private var groupHideTask: Task<Void, Never>?
    private var nowPlayingPanel: NonActivatingPanel?
    private var nowPlayingHosting: NSView?
    private var nowPlayingHideTask: Task<Void, Never>?
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
        nowPlayingModel: NowPlayingPopoverViewModel,
        permissions: any PermissionChecking,
        configuration: ConfigurationController,
        events: EventBus
    ) {
        self.model = model
        self.flyoutModel = flyoutModel
        self.groupModel = groupModel
        self.nowPlayingModel = nowPlayingModel
        self.permissions = permissions
        self.configuration = configuration
        self.events = events
    }

    // MARK: - Lifecycle

    public func start() {
        model.layoutDidChange = { [weak self] in self?.reframe(animated: false) }
        model.onHoverChange = { [weak self] hovering in self?.hoverChanged(hovering) }

        let panel = NonActivatingPanel(contentView: FirstMouseHostingView(rootView: SidebarView(model: model)))
        sidebarPanel = panel

        let edge = EdgeTriggerPanel { [weak self] in self?.reveal() }
        edgePanel = edge

        model.showWindows = { [weak self] identity in self?.showFlyout(for: identity) }
        model.scheduleFlyoutHide = { [weak self] in self?.scheduleFlyoutHide() }
        flyoutModel.onDismiss = { [weak self] in self?.hideFlyout() }
        flyoutModel.onContentChange = { [weak self] in self?.layoutFlyout() }
        let flyoutHostingView = FirstMouseHostingView(
            rootView: WindowFlyoutView(model: flyoutModel, permissions: permissions)
                .onHover { [weak self] hovering in self?.flyoutHoverChanged(hovering) }
        )
        flyoutHosting = flyoutHostingView
        flyoutPanel = NonActivatingPanel(contentView: flyoutHostingView)

        model.showGroup = { [weak self] group in self?.showGroup(group) }
        groupModel.onDismiss = { [weak self] in self?.hideGroup() }
        let groupHostingView = FirstMouseHostingView(
            rootView: GroupPopoverView(model: groupModel)
                .onHover { [weak self] hovering in self?.groupHoverChanged(hovering) }
        )
        groupHosting = groupHostingView
        groupPanel = NonActivatingPanel(contentView: groupHostingView)

        model.showNowPlaying = { [weak self] playing in self?.showNowPlaying(playing) }
        model.hideNowPlaying = { [weak self] in self?.nowPlayingModel.hide() }
        nowPlayingModel.onDismiss = { [weak self] in self?.hideNowPlayingPanel() }
        let nowPlayingHostingView = FirstMouseHostingView(
            rootView: NowPlayingPopoverView(model: nowPlayingModel)
                .onHover { [weak self] hovering in self?.nowPlayingHoverChanged(hovering) }
        )
        nowPlayingHosting = nowPlayingHostingView
        nowPlayingPanel = NonActivatingPanel(contentView: nowPlayingHostingView)

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
        panel.orderFrontRegardless()
        updateEdgePanel()
        Log.sidebar.notice("Sidebar panel shown")
    }

    public func stop() {
        hideTask?.cancel()
        flyoutHideTask?.cancel()
        eventTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        groupHideTask?.cancel()
        nowPlayingHideTask?.cancel()
        sidebarPanel?.orderOut(nil)
        edgePanel?.orderOut(nil)
        flyoutPanel?.orderOut(nil)
        groupPanel?.orderOut(nil)
        nowPlayingPanel?.orderOut(nil)
    }

    // MARK: - Now playing

    private func showNowPlaying(_ playing: NowPlaying) {
        nowPlayingHideTask?.cancel()
        hideFlyout()
        nowPlayingModel.show(playing)
        layoutNowPlaying()
        nowPlayingPanel?.orderFrontRegardless()
    }

    private func hideNowPlayingPanel() {
        nowPlayingHideTask?.cancel()
        nowPlayingHideTask = nil
        nowPlayingPanel?.orderOut(nil)
    }

    private func nowPlayingHoverChanged(_ hovering: Bool) {
        guard !hovering else {
            nowPlayingHideTask?.cancel()
            nowPlayingHideTask = nil
            return
        }
        nowPlayingHideTask?.cancel()
        nowPlayingHideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.nowPlayingModel.hide()
        }
    }

    /// Keeps an open flyout in step with the track, and follows the row when the bar moves.
    public func nowPlayingChanged() {
        nowPlayingModel.update(model.nowPlaying)
        guard nowPlayingModel.isShowing else { return }
        layoutNowPlaying()
    }

    private func layoutNowPlaying() {
        guard let panel = nowPlayingPanel,
              let hosting = nowPlayingHosting,
              let sidebar = sidebarPanel,
              let screen = targetScreen,
              nowPlayingModel.isShowing
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
                anchor: anchorOffset(forRow: Self.nowPlayingRowID),
                in: screen.visibleFrame,
                position: model.appearance.position
            ),
            display: true
        )
    }

    /// The now-playing row is not an application, so it has no bundle identifier to anchor on. It
    /// is the first row of the tail, which `anchorOffset` finds by falling through to the last
    /// section.
    static let nowPlayingRowID = "com.congbui.nexus.now-playing"

    // MARK: - Group popover

    private func showGroup(_ group: SidebarGroup) {
        groupHideTask?.cancel()
        hideFlyout()
        groupModel.show(group)
        layoutGroup()
        groupPanel?.orderFrontRegardless()
    }

    private func hideGroup() {
        groupHideTask?.cancel()
        groupHideTask = nil
        groupPanel?.orderOut(nil)
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
    private func scheduleGroupHide() {
        guard groupModel.group != nil else { return }
        groupHideTask?.cancel()
        groupHideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.groupModel.hide()
        }
    }

    /// The popover follows its group: an edit that renames it, empties it or dissolves it has to
    /// be reflected before the next frame, or the panel shows a dock that no longer exists.
    public func groupsChanged() {
        groupModel.update(from: model.pinned)
        guard groupModel.group != nil else { return }
        layoutGroup()
    }

    private func layoutGroup() {
        guard let panel = groupPanel,
              let hosting = groupHosting,
              let sidebar = sidebarPanel,
              let screen = targetScreen,
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
              let sidebar = sidebarPanel,
              let screen = targetScreen,
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

    /// Distance to the centre of the row that *draws* `id` — which for an application inside a
    /// group is the group's row, not one of its own.
    private func anchorOffset(forRow id: String) -> CGFloat {
        let counts = model.sectionRowCounts
        // The now-playing row is not an application: it is the first row of the tail.
        if id == Self.nowPlayingRowID {
            let sections = counts.filter { $0 > 0 }
            return SidebarLayout.rowCentre(
                sectionRowCounts: counts,
                section: max(0, sections.count - 1),
                row: 0,
                appearance: model.appearance
            )
        }
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

    public func toggleSidebar() {
        isSuppressed.toggle()
        if isSuppressed {
            sidebarPanel?.orderOut(nil)
            edgePanel?.orderOut(nil)
            onBarFrameChange?()
        } else {
            reframe(animated: false)
            sidebarPanel?.orderFrontRegardless()
            updateEdgePanel()
        }
    }

    // MARK: - Geometry

    /// Target screen for the sidebar, honouring the stored display preference (D11).
    private var targetScreen: NSScreen? {
        DisplayService.screen(for: configuration.configuration.appearance.display)
    }

    public func reframe(animated: Bool) {
        guard let panel = sidebarPanel, let screen = targetScreen, !isSuppressed else { return }
        let appearance = model.appearance
        // The bar's zones depend on how much screen there is along its own axis (M14), which only
        // this knows.
        let visible = screen.visibleFrame
        model.availableExtent = (appearance.position.isVertical ? visible.height : visible.width)
            - SidebarLayout.screenMargin * 2
        let size = SidebarLayout.size(
            zones: model.zones,
            appearance: appearance,
            expanded: model.isExpanded
        )
        let frame = SidebarLayout.frame(
            size: size,
            in: screen.visibleFrame,
            position: appearance.position,
            hidden: !isRevealed
        )
        setFrame(frame, on: panel, animated: animated)
        updateEdgePanel()
        onBarFrameChange?()
        if groupModel.group != nil { layoutGroup() }
        if nowPlayingModel.isShowing { layoutNowPlaying() }
    }

    /// What Reserved Space needs to know: where the bar is, and on which screen. `nil` whenever
    /// the bar is not really there — suppressed, hidden, or auto-hiding, which reserves nothing.
    public var reservedSpaceGeometry: ReservedSpaceController.Geometry? {
        guard let panel = sidebarPanel,
              let screen = targetScreen,
              !isSuppressed,
              isRevealed,
              !configuration.configuration.behavior.autoHide
        else { return nil }
        return ReservedSpaceController.Geometry(
            bar: panel.frame,
            visible: screen.visibleFrame,
            display: screen.frame,
            position: model.appearance.position
        )
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
        guard let edge = edgePanel, let screen = targetScreen else { return }
        let autoHide = configuration.configuration.behavior.autoHide
        guard autoHide, !isSuppressed else {
            edge.orderOut(nil)
            return
        }
        edge.setFrame(
            SidebarLayout.edgeTriggerFrame(
                in: screen.visibleFrame,
                position: model.appearance.position
            ),
            display: false
        )
        edge.orderFrontRegardless()
    }

    // MARK: - Auto-hide

    private func applyBehavior() {
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
        sidebarPanel?.orderFrontRegardless()
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
