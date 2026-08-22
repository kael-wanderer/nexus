import AppKit
import NexusCore
import SwiftUI

/// The only code in Nexus that touches `NSWindow`. Panels are created once and reused, so the
/// hotkey path never pays a window-creation cost (DESIGN_MVP §2.3).
@MainActor
public final class PanelController {
    private let model: SidebarViewModel
    private let configuration: ConfigurationController
    private let events: EventBus

    private var sidebarPanel: SidebarPanel?
    private var edgePanel: EdgeTriggerPanel?
    private var hideTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var screenObserver: (any NSObjectProtocol)?

    /// Session-only: the status-item "Toggle Sidebar" hides the panel without changing settings.
    private var isSuppressed = false
    /// Auto-hide state. Always true when auto-hide is off.
    private var isRevealed = true

    public init(
        model: SidebarViewModel,
        configuration: ConfigurationController,
        events: EventBus
    ) {
        self.model = model
        self.configuration = configuration
        self.events = events
    }

    // MARK: - Lifecycle

    public func start() {
        model.layoutDidChange = { [weak self] in self?.reframe(animated: false) }
        model.onHoverChange = { [weak self] hovering in self?.hoverChanged(hovering) }

        let panel = SidebarPanel(contentView: FirstMouseHostingView(rootView: SidebarView(model: model)))
        sidebarPanel = panel

        let edge = EdgeTriggerPanel { [weak self] in self?.reveal() }
        edgePanel = edge

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

        eventTask = Task { [weak self, events] in
            for await event in events.events() {
                guard let self else { return }
                if case .configurationChanged = event { self.applyBehavior() }
            }
        }

        isRevealed = !configuration.configuration.behavior.autoHide
        reframe(animated: false)
        panel.orderFrontRegardless()
        updateEdgePanel()
        Log.sidebar.info("Sidebar panel shown")
    }

    public func stop() {
        hideTask?.cancel()
        eventTask?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        sidebarPanel?.orderOut(nil)
        edgePanel?.orderOut(nil)
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
