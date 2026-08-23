import AppKit
import SwiftUI

/// Settings and onboarding are ordinary titled windows, not panels — these two *should* be
/// focused, and standard AppKit controls only render correctly in a key window. An `.accessory`
/// application has to activate itself explicitly to give them focus.
@MainActor
public final class AuxiliaryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let makeContent: () -> AnyView
    private var onClose: (() -> Void)?
    /// Whoever was in front before this window took the focus, so closing can hand it back
    /// without hiding the application (D93).
    private var previousApplication: NSRunningApplication?

    public init(title: String, content: @escaping () -> some View) {
        self.title = title
        self.makeContent = { AnyView(content()) }
        super.init()
    }

    public var isVisible: Bool { window?.isVisible ?? false }

    public func show(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        if !NSApp.isActive { previousApplication = NSWorkspace.shared.frontmostApplication }
        let window = self.window ?? makeWindow()
        self.window = window
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    public func close() {
        window?.close()
    }

    public func stop() {
        window?.delegate = nil
        window?.close()
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingView(rootView: makeContent())
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary]
        return window
    }

    public func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
        // An agent app that stays "active" with no visible window feels stuck, so focus goes back
        // where it came from — by activating that application, not by hiding this one.
        //
        // `NSApp.hide(nil)` was the first answer and it was wrong twice over (D93): it hid the bars
        // along with the window, leaving the menu-bar item as the only sign Nexus was running; and
        // an application flagged hidden publishes no windows to the accessibility tree, so
        // VoiceOver lost the bar as well.
        if let previousApplication, previousApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApplication.activate()
        } else {
            NSApp.deactivate()
        }
        previousApplication = nil
    }
}
