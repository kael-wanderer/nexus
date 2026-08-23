import AppKit
import NexusCore
import SwiftUI

/// Unlike the sidebar, the palette *must* take keyboard focus — and give it back.
public final class SearchPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public init(contentView: NSView, title: String = "Nexus Search") {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: SearchPaletteView.width, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        // .fullScreenAuxiliary is what lets the palette appear over a fullscreen app WITHOUT
        // switching Spaces — the most noticeable failure mode of a badly built palette.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = false
        animationBehavior = .none
        hasShadow = true
        isReleasedWhenClosed = false
        // Never hidden by `NSApp.hide(nil)` along with the rest of the application (D93).
        canHide = false
        self.title = title
        self.contentView = contentView
    }
}

@MainActor
public final class SearchPanelController {
    /// Review Note 1. The non-activating path is strictly better when it works: the frontmost
    /// application never deactivates, so there is no restore step and no focus flicker. It is
    /// tried first, and falls back the first time the panel does not actually become key.
    public enum ActivationStrategy: String, Sendable {
        case nonActivating
        case activateAndRestore
    }

    private let model: SearchViewModel
    private var panel: SearchPanel?
    private var hosting: NSView?
    private var previousApplication: NSRunningApplication?
    private var digitMonitor: Any?
    private var outsideClickMonitor: Any?
    private var resignObserver: (any NSObjectProtocol)?
    private var verificationTask: Task<Void, Never>?

    /// Where the palette appears. The global shortcut always centres it — that is what pressing a
    /// hotkey means, and it is what Spotlight does (D90) — and the bar's own Search part opens it
    /// beside itself.
    public enum Placement: Sendable {
        case centred
        case bar
    }

    private var placement: Placement = .centred

    public private(set) var strategy: ActivationStrategy = .nonActivating
    public private(set) var isVisible = false
    /// Injected so the palette can refresh the window snapshot the moment it opens.
    public var willShow: (() -> Void)?
    /// Where the bar's Search row is, when there is a bar on screen. Supplied by the controller
    /// that owns the bar; `nil` means "no bar to anchor to", and the palette goes back to the
    /// middle of the screen (M19).
    public var barAnchor: (() -> SidebarLayout.BarAnchor?)?

    public init(model: SearchViewModel) {
        self.model = model
    }

    public func start() {
        let hostingView = FirstMouseHostingView(rootView: SearchPaletteView(model: model))
        hosting = hostingView
        panel = SearchPanel(contentView: hostingView)
        model.onResultsChanged = { [weak self] in self?.resize() }
        model.onClose = { [weak self] in self?.hide(restoreFocus: true) }
        // Picking a scope from the menu takes first responder; the field gets it straight back —
        // without selecting what is in it, which would make the next keystroke replace the query.
        model.onScopeChanged = { [weak self] in
            guard let self, let panel = self.panel, self.isVisible,
                  let field = Self.firstTextField(in: panel.contentView),
                  panel.firstResponder !== field.currentEditor()
            else { return }
            panel.makeFirstResponder(field)
        }
    }

    public func stop() {
        verificationTask?.cancel()
        removeDigitMonitor()
        removeDismissMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    public func toggle(_ placement: Placement = .centred) {
        if isVisible { hide(restoreFocus: true) } else { show(placement) }
    }

    public func show(_ placement: Placement = .centred) {
        guard let panel else { return }
        self.placement = placement
        willShow?()

        // Capture BEFORE anything can change the frontmost application.
        previousApplication = NSWorkspace.shared.frontmostApplication
        model.prepareForDisplay()
        position(panel)

        if strategy == .activateAndRestore {
            NSApp.activate()
        }
        panel.makeKeyAndOrderFront(nil)
        focusField(in: panel)
        installDigitMonitor()
        installDismissMonitors(panel)
        isVisible = true
        resize()

        // Key status does not settle synchronously, so the prototype is measured a beat later:
        // if a non-activating panel did not actually become key the user cannot type, and the
        // strategy switches permanently for this session.
        verificationTask?.cancel()
        verificationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, let panel = self.panel, self.isVisible else { return }
            Log.search.notice(
                "Palette state: strategy \(self.strategy.rawValue, privacy: .public), key \(panel.isKeyWindow, privacy: .public), app active \(NSApp.isActive, privacy: .public), frontmost \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none", privacy: .public)"
            )
            guard self.strategy == .nonActivating, !panel.isKeyWindow else { return }
            Log.search.notice("Non-activating palette did not become key; switching to activate-and-restore")
            self.strategy = .activateAndRestore
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            self.focusField(in: panel)
        }
    }

    /// `restoreFocus` is false when the executed action activates something else — that target is
    /// the intended destination.
    public func hide(restoreFocus: Bool) {
        guard let panel, isVisible else { return }
        verificationTask?.cancel()
        verificationTask = nil
        removeDigitMonitor()
        removeDismissMonitors()
        panel.orderOut(nil)
        isVisible = false
        model.reset()

        if restoreFocus, strategy == .activateAndRestore {
            // Explicit reactivation rather than NSApp.hide: `hide` restores whichever app macOS
            // picks, which is not always the one the user came from.
            previousApplication?.activate()
        }
        previousApplication = nil
    }

    // MARK: - Dismissal

    /// A click anywhere but the palette closes it, and so does losing key status.
    ///
    /// Neither happens on its own: `hidesOnDeactivate` is off, because the palette has to survive
    /// the flicker of activating, and clicks in another application never reach a panel that is not
    /// theirs. Without this the palette stays on screen until Escape — which is what it did.
    private func installDismissMonitors(_ panel: SearchPanel) {
        removeDismissMonitors()

        // Global monitors see clicks in *other* applications. Clicks inside the palette arrive as
        // local events instead, so "global" is exactly "outside" here — except for Nexus's own
        // panels, which is why the frame is checked too.
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
                // Command-Tab, a click that activated another application, a hotkey elsewhere: the
                // palette has lost the keyboard, so it has nothing left to do.
                self.hide(restoreFocus: false)
            }
        }
    }

    private func removeDismissMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    // MARK: - Geometry

    /// Beside the bar's Search row when the setting asks for it, and otherwise on the display
    /// containing the pointer, regardless of the sidebar's display — that is where the user is
    /// looking.
    private func position(_ panel: SearchPanel) {
        if let anchor = currentAnchor() {
            panel.setFrame(anchor.frame(for: panel.frame.size), display: true)
            return
        }
        guard let screen = DisplayService.screenContainingMouse() ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + frame.height * 0.62 - size.height / 2
            )
        )
    }

    private func currentAnchor() -> SidebarLayout.BarAnchor? {
        guard placement == .bar else { return nil }
        return barAnchor?()
    }

    private func resize() {
        guard let panel, let hosting, isVisible else { return }
        hosting.layoutSubtreeIfNeeded()
        let height = max(hosting.fittingSize.height, SearchPaletteView.fieldHeight)
        guard abs(height - panel.frame.height) > 0.5 else { return }
        let size = CGSize(width: SearchPaletteView.width, height: height)
        // Anchored to a row, the palette is re-placed rather than grown: a list that gets longer
        // has to stay attached to the bar, which for a bottom bar means growing *upwards*.
        if let anchor = currentAnchor() {
            panel.setFrame(anchor.frame(for: size), display: true)
            return
        }
        // Grow downwards from a stable top edge.
        let top = panel.frame.maxY
        panel.setFrame(
            NSRect(x: panel.frame.minX, y: top - height, width: size.width, height: height),
            display: true
        )
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

    // MARK: - ⌘1…⌘9 and ⌃1…⌃6

    /// Two digit chords, and they must not be the same one: `⌘` runs the numbered result, `⌃`
    /// picks a scope (D87). The menu carries the same shortcuts for display, and repeating a
    /// scope that is already set is a no-op, so a double delivery costs nothing.
    private func installDigitMonitor() {
        removeDigitMonitor()
        digitMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible,
                  let characters = event.charactersIgnoringModifiers,
                  let digit = Int(characters)
            else { return event }
            switch event.modifierFlags.intersection(.deviceIndependentFlagsMask) {
            case .command where (1...9).contains(digit):
                self.model.selectRow(digit - 1)
                return nil
            case .control where SearchScope.scope(forShortcut: digit) != nil:
                self.model.selectScope(shortcut: digit)
                return nil
            default:
                return event
            }
        }
    }

    private func removeDigitMonitor() {
        if let digitMonitor { NSEvent.removeMonitor(digitMonitor) }
        digitMonitor = nil
    }
}
