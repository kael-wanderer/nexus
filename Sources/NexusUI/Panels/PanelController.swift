import AppKit
import NexusCore
import SwiftUI

/// The only code in Nexus that touches `NSWindow`. Panels are created once and reused, so the
/// hotkey path never pays a window-creation cost (DESIGN_MVP §2.3).
@MainActor
public final class PanelController {
    private let model: SidebarViewModel
    private let flyoutModel: WindowFlyoutViewModel
    private let permissions: any PermissionChecking
    private let configuration: ConfigurationController
    private let events: EventBus

    private var sidebarPanel: NonActivatingPanel?
    private var edgePanel: EdgeTriggerPanel?
    private var flyoutPanel: NonActivatingPanel?
    private var flyoutHosting: NSView?
    private var flyoutHideTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var screenObserver: (any NSObjectProtocol)?

    /// Session-only: the status-item "Toggle Sidebar" hides the panel without changing settings.
    private var isSuppressed = false
    /// Auto-hide state. Always true when auto-hide is off.
    private var isRevealed = true

    public init(
        model: SidebarViewModel,
        flyoutModel: WindowFlyoutViewModel,
        permissions: any PermissionChecking,
        configuration: ConfigurationController,
        events: EventBus
    ) {
        self.model = model
        self.flyoutModel = flyoutModel
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
        flyoutModel.onDismiss = { [weak self] in self?.hideFlyout() }
        flyoutModel.onContentChange = { [weak self] in self?.layoutFlyout() }
        let flyoutHostingView = FirstMouseHostingView(
            rootView: WindowFlyoutView(model: flyoutModel, permissions: permissions)
                .onHover { [weak self] hovering in self?.flyoutHoverChanged(hovering) }
        )
        flyoutHosting = flyoutHostingView
        flyoutPanel = NonActivatingPanel(contentView: flyoutHostingView)

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
        sidebarPanel?.orderOut(nil)
        edgePanel?.orderOut(nil)
        flyoutPanel?.orderOut(nil)
    }

    // MARK: - Window flyout

    private func showFlyout(for identity: ApplicationIdentity) {
        guard let item = (model.pinned + model.running).first(where: { $0.identity == identity })
        else { return }
        flyoutHideTask?.cancel()
        flyoutModel.show(identity, name: item.name)
        layoutFlyout()
        flyoutPanel?.orderFrontRegardless()
    }

    private func hideFlyout() {
        flyoutHideTask?.cancel()
        flyoutHideTask = nil
        flyoutPanel?.orderOut(nil)
    }

    private func flyoutHoverChanged(_ hovering: Bool) {
        if hovering {
            flyoutHideTask?.cancel()
            flyoutHideTask = nil
            return
        }
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
        let size = CGSize(
            width: WindowFlyoutView.width,
            height: max(hosting.fittingSize.height, WindowFlyoutView.rowHeight)
        )
        panel.setFrame(
            SidebarLayout.flyoutFrame(
                size: size,
                beside: sidebar.frame,
                anchorFromTop: anchorOffset(for: identity),
                in: screen.visibleFrame,
                position: model.appearance.position
            ),
            display: true
        )
    }

    private func anchorOffset(for identity: ApplicationIdentity) -> CGFloat {
        let counts = model.sectionRowCounts
        if let row = model.pinned.firstIndex(where: { $0.identity == identity }) {
            return SidebarLayout.rowCentreFromTop(
                sectionRowCounts: counts,
                section: 0,
                row: row,
                appearance: model.appearance
            )
        }
        if let row = model.running.firstIndex(where: { $0.identity == identity }) {
            return SidebarLayout.rowCentreFromTop(
                sectionRowCounts: counts,
                section: model.pinned.isEmpty ? 0 : 1,
                row: row,
                appearance: model.appearance
            )
        }
        return (sidebarPanel?.frame.height ?? 0) / 2
    }

    public func toggleSidebar() {
        isSuppressed.toggle()
        if isSuppressed {
            sidebarPanel?.orderOut(nil)
            edgePanel?.orderOut(nil)
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
        let size = SidebarLayout.size(
            sectionRowCounts: model.sectionRowCounts,
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
