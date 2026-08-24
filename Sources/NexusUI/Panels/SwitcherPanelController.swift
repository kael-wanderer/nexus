import AppKit
import NexusCore
import SwiftUI

/// Like the palette, the switcher must take the keyboard and give it back (design/window-switcher.md
/// §2).
public final class SwitcherPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        // .fullScreenAuxiliary is what lets the switcher appear over a fullscreen app WITHOUT
        // switching Spaces, same as the palette (SearchPanel).
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = false
        animationBehavior = .none
        hasShadow = false
        isReleasedWhenClosed = false
        // Never hidden by `NSApp.hide(nil)` along with the rest of the application (D93), same as
        // the palette.
        canHide = false
        title = String(localized: "Nexus Window Switcher")
        self.contentView = contentView
    }
}

@MainActor
public final class SwitcherPanelController {
    /// Review Note 1 of `SearchPanelController` applies here too: the non-activating path is tried
    /// first because it never deactivates the frontmost application, and falls back permanently for
    /// this session the first time the panel does not actually become key.
    public enum ActivationStrategy: String, Sendable {
        case nonActivating
        case activateAndRestore
    }

    private let model: SwitcherViewModel
    private var panel: SwitcherPanel?
    private var previousApplication: NSRunningApplication?
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var resignObserver: (any NSObjectProtocol)?
    private var verificationTask: Task<Void, Never>?

    public private(set) var strategy: ActivationStrategy = .nonActivating
    public private(set) var isVisible = false

    public init(model: SwitcherViewModel) {
        self.model = model
    }

    public func start() {
        let hosting = FirstMouseHostingView(rootView: SwitcherView(model: model))
        panel = SwitcherPanel(contentView: hosting)
        model.onClose = { [weak self] in self?.hide(restoreFocus: true) }
        model.start()
    }

    public func stop() {
        model.stop()
        verificationTask?.cancel()
        verificationTask = nil
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    public func toggle() {
        if isVisible { hide(restoreFocus: true) } else { show() }
    }

    public func show() {
        guard let panel else { return }
        // Capture BEFORE anything can change the frontmost application.
        previousApplication = NSWorkspace.shared.frontmostApplication
        model.prepareForDisplay()

        let screen = DisplayService.screenContainingMouse() ?? NSScreen.main
        if let screen { panel.setFrame(Self.frame(for: screen.visibleFrame), display: true) }

        if strategy == .activateAndRestore {
            NSApp.activate()
        }
        panel.makeKeyAndOrderFront(nil)
        installMonitors(panel)
        isVisible = true
        model.focusFirst()

        // Key status does not settle synchronously, so the prototype is measured a beat later,
        // exactly as the palette does: if a non-activating panel did not actually become key the
        // user cannot type, and the strategy switches permanently for this session.
        verificationTask?.cancel()
        verificationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, let panel = self.panel, self.isVisible else { return }
            guard self.strategy == .nonActivating, !panel.isKeyWindow else { return }
            Log.windows.notice("Non-activating switcher did not become key; switching to activate-and-restore")
            self.strategy = .activateAndRestore
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// `restoreFocus` is false when a card was clicked: that window is the destination, and it has
    /// already been raised.
    public func hide(restoreFocus: Bool) {
        guard let panel, isVisible else { return }
        verificationTask?.cancel()
        verificationTask = nil
        removeMonitors()
        panel.orderOut(nil)
        isVisible = false
        if restoreFocus, strategy == .activateAndRestore { previousApplication?.activate() }
        previousApplication = nil
    }

    /// The whole visible area. Not `screen.frame`: the menu bar stays where it is, because a
    /// switcher that hides it looks like a crash for the half-second before it is read.
    public nonisolated static func frame(for visibleFrame: CGRect) -> CGRect { visibleFrame }

    // MARK: - Keyboard and dismissal

    /// The filter field holds first responder the whole time, so the arrows and `Return`/`Escape`/
    /// `⌘W` are taken before it sees them — the same local monitor the palette uses for its digit
    /// chords (design/window-switcher.md §8).
    private func installMonitors(_ panel: SwitcherPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            switch Int(event.keyCode) {
            case 123: self.model.moveFocus(.left, columns: self.model.columns); return nil
            case 124: self.model.moveFocus(.right, columns: self.model.columns); return nil
            case 125: self.model.moveFocus(.down, columns: self.model.columns); return nil
            case 126: self.model.moveFocus(.up, columns: self.model.columns); return nil
            case 36, 76: self.model.activateFocused(); return nil                     // Return, Enter
            case 53: self.model.clearQueryOrClose(); return nil                       // Escape
            case 13 where event.modifierFlags.contains(.command):                     // ⌘W
                Task { await self.model.closeFocused() }
                return nil
            default:
                return event
            }
        }

        // Global monitors see clicks in *other* applications; a click inside this panel arrives as
        // a local event instead (the background-dismiss gesture in `SwitcherView`), so "global" is
        // exactly "outside" here — same reasoning as `SearchPanelController`.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, self.isVisible else { return }
                guard !panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.hide(restoreFocus: false)
            }
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                // Command-Tab, a click elsewhere, another hotkey: the panel has lost the keyboard
                // and has nothing left to do.
                self.hide(restoreFocus: false)
            }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }
}
