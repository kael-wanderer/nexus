import AppKit
import SwiftUI

/// One menu item carrying its own closure, so callers do not need an `@objc` target.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, isEnabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        self.isEnabled = isEnabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not supported") }

    @objc private func fire() { handler() }
}

/// SwiftUI's `.contextMenu` can activate the hosting application. `NSMenu.popUp` runs its own
/// event loop from a non-key window and never activates Nexus, which is what the sidebar's
/// no-focus-theft guarantee requires (DESIGN_MVP §2.1).
struct ContextMenuCatcher: NSViewRepresentable {
    let items: () -> [NSMenuItem]

    func makeNSView(context: Context) -> NSView {
        CatcherView(items: items)
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? CatcherView)?.items = items
    }

    final class CatcherView: NSView {
        var items: () -> [NSMenuItem]

        init(items: @escaping () -> [NSMenuItem]) {
            self.items = items
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not supported") }

        /// Transparent to everything except a right click, so the SwiftUI row underneath keeps
        /// receiving ordinary clicks and hover.
        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseUp:
                return super.hitTest(point)
            default:
                return nil
            }
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func rightMouseDown(with event: NSEvent) {
            let menu = NSMenu()
            for item in items() { menu.addItem(item) }
            guard !menu.items.isEmpty else { return }
            menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
        }
    }
}

extension View {
    /// Attaches an AppKit context menu that does not activate the application.
    func nexusContextMenu(_ items: @escaping () -> [NSMenuItem]) -> some View {
        overlay(ContextMenuCatcher(items: items))
    }
}
