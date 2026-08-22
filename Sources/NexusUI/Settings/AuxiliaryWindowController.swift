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

    public init(title: String, content: @escaping () -> some View) {
        self.title = title
        self.makeContent = { AnyView(content()) }
        super.init()
    }

    public var isVisible: Bool { window?.isVisible ?? false }

    public func show(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
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
        // An agent app that stays "active" with no visible window feels stuck; hand focus back.
        NSApp.hide(nil)
    }
}
