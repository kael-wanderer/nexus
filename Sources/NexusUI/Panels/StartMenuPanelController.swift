import AppKit
import NexusCore
import SwiftUI

/// The start menu is a keyboard surface — it has a text field — so it follows the palette's focus
/// design rather than the sidebar's: it takes focus deliberately and gives it back on the way out
/// (`design/mvp.md` §2.2).
@MainActor
public final class StartMenuPanelController {
    private let model: StartMenuViewModel
    private let configuration: ConfigurationController

    private var panel: SearchPanel?
    private var previousApplication: NSRunningApplication?
    private var resignObserver: (any NSObjectProtocol)?

    public private(set) var isVisible = false

    public init(model: StartMenuViewModel, configuration: ConfigurationController) {
        self.model = model
        self.configuration = configuration
    }

    public func start() {
        panel = SearchPanel(
            contentView: FirstMouseHostingView(rootView: StartMenuView(model: model)),
            title: String(localized: "Nexus start menu")
        )
        model.onClose = { [weak self] in self?.hide(restoreFocus: true) }
        model.onContentChange = { [weak self] in self?.resize() }

        // Clicking anywhere else closes it, the way a menu does.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide(restoreFocus: false) }
        }
    }

    public func stop() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    public func toggle() {
        if isVisible { hide(restoreFocus: true) } else { show() }
    }

    public func show() {
        guard let panel else { return }
        previousApplication = NSWorkspace.shared.frontmostApplication
        model.prepareForDisplay()
        resize()
        position(panel)

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        focusField(in: panel)
        isVisible = true
        Log.app.notice("Start menu shown")
    }

    public func hide(restoreFocus: Bool) {
        guard let panel, isVisible else { return }
        panel.orderOut(nil)
        isVisible = false
        model.reset()
        // Launching activates the target application; restoring focus then would fight it.
        if restoreFocus { previousApplication?.activate() }
        previousApplication = nil
    }

    // MARK: - Geometry

    private func position(_ panel: SearchPanel) {
        guard let screen = DisplayService.screenContainingMouse() ?? NSScreen.main else { return }
        panel.setFrame(
            StartMenuLayout.frame(
                size: panel.frame.size,
                in: screen.visibleFrame,
                corner: configuration.configuration.appearance.startMenuCorner
            ),
            display: true
        )
    }

    private func resize() {
        guard let panel else { return }
        let height = StartMenuView.height(forApplications: model.applications.count)
        guard abs(height - panel.frame.height) > 0.5 else { return }
        panel.setFrame(
            NSRect(
                x: panel.frame.minX,
                y: panel.frame.minY,
                width: StartMenuView.width,
                height: height
            ),
            display: true
        )
        if isVisible { position(panel) }
    }

    private func focusField(in panel: SearchPanel) {
        guard let field = Self.firstTextField(in: panel.contentView) else { return }
        panel.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private static func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField { return field }
        for subview in view.subviews {
            if let found = firstTextField(in: subview) { return found }
        }
        return nil
    }
}
