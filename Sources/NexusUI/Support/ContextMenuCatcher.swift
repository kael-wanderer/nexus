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

/// Click and context-menu handling for rows inside a panel that can never become key.
///
/// Two AppKit facts make this necessary rather than decorative:
///
/// 1. A click into a non-key window is swallowed unless the **view that is hit** returns
///    `acceptsFirstMouse == true`. Overriding it on the `NSHostingView` is not enough, because
///    the hit view is one of SwiftUI's internal subviews. The sidebar and the flyout can never
///    become key, so *every* click is a first-mouse click — meaning SwiftUI's `.onTapGesture`
///    never fires there at all, not merely on the first click.
/// 2. SwiftUI's `.contextMenu` can activate the hosting application, which would break the
///    sidebar's no-focus-theft guarantee. `NSMenu.popUp` runs its own event loop and does not.
struct PanelRowInteraction: NSViewRepresentable {
    let onClick: (() -> Void)?
    let items: () -> [NSMenuItem]

    func makeNSView(context: Context) -> NSView {
        CatcherView(onClick: onClick, items: items)
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? CatcherView else { return }
        view.onClick = onClick
        view.items = items
    }

    final class CatcherView: NSView {
        var onClick: (() -> Void)?
        var items: () -> [NSMenuItem]
        private var mouseDownLocation: NSPoint?

        /// Squared distance, in points, a press may travel and still count as a click.
        private static let clickSlopSquared: CGFloat = 25

        init(onClick: (() -> Void)?, items: @escaping () -> [NSMenuItem]) {
            self.onClick = onClick
            self.items = items
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not supported") }

        /// Claims mouse presses only. Hover, scrolling and drag-and-drop fall through to the
        /// SwiftUI row underneath, which still owns the highlight and the reorder drop target.
        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp:
                return super.hitTest(point)
            default:
                return nil
            }
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownLocation = event.locationInWindow
        }

        override func mouseUp(with event: NSEvent) {
            defer { mouseDownLocation = nil }
            guard let onClick, let start = mouseDownLocation else { return }
            let dx = event.locationInWindow.x - start.x
            let dy = event.locationInWindow.y - start.y
            guard dx * dx + dy * dy <= Self.clickSlopSquared else { return }
            onClick()
        }

        override func rightMouseDown(with event: NSEvent) {
            let menu = NSMenu()
            for item in items() { menu.addItem(item) }
            guard !menu.items.isEmpty else { return }
            menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
        }
    }
}

extension View {
    /// Click and context-menu handling that works inside a panel that never becomes key.
    func nexusRow(
        onClick: (() -> Void)? = nil,
        menu: @escaping () -> [NSMenuItem] = { [] }
    ) -> some View {
        overlay(PanelRowInteraction(onClick: onClick, items: menu))
    }
}
