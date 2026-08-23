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
    /// What this row puts on the pasteboard when dragged. `nil` means the row cannot be dragged.
    var dragPayload: String?
    var dragImage: NSImage?
    /// Another row's payload was dropped on this one.
    var onDrop: ((String) -> Void)?
    /// A drag started from this row.
    var onDragBegin: ((String) -> Void)?
    /// A drag is hovering this row, and *where* in the row it is — drives the live preview order
    /// and the grouping zone (D103). The point is normalised 0…1 inside the row, measured from its
    /// top-left corner, so `y` runs along a vertical bar and `x` along a horizontal one.
    var onDragOver: ((String, CGPoint) -> Void)?
    /// The drag that started here ended; `true` when it was accepted by a row.
    var onDragEnd: ((Bool) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView(onClick: onClick, items: items)
        update(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? CatcherView else { return }
        view.onClick = onClick
        view.items = items
        update(view)
    }

    private func update(_ view: CatcherView) {
        view.dragPayload = dragPayload
        view.dragImage = dragImage
        view.onDrop = onDrop
        view.onDragBegin = onDragBegin
        view.onDragOver = onDragOver
        view.onDragEnd = onDragEnd
    }

    final class CatcherView: NSView, NSDraggingSource {
        var onClick: (() -> Void)?
        var items: () -> [NSMenuItem]
        var dragPayload: String?
        var dragImage: NSImage?
        var onDrop: ((String) -> Void)? {
            didSet { registerDropTypes() }
        }
        var onDragBegin: ((String) -> Void)?
        var onDragOver: ((String, CGPoint) -> Void)?
        var onDragEnd: ((Bool) -> Void)?

        private var mouseDownLocation: NSPoint?
        private var isDragging = false

        /// Squared distance, in points, a press may travel and still count as a click.
        private static let clickSlopSquared: CGFloat = 25

        /// The pasteboard type for a row being dragged inside the sidebar. Private to Nexus, so a
        /// stray text drag from another application can never reorder anything.
        static let rowType = NSPasteboard.PasteboardType("com.congbui.nexus.sidebar-row")

        init(onClick: (() -> Void)?, items: @escaping () -> [NSMenuItem]) {
            self.onClick = onClick
            self.items = items
            super.init(frame: .zero)
        }

        private func registerDropTypes() {
            if onDrop == nil {
                unregisterDraggedTypes()
            } else {
                registerForDraggedTypes([Self.rowType])
            }
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

        /// A press that travels far enough becomes a drag instead of a click. `mouseUp`'s slop
        /// check then rejects the same gesture, so a drag never also activates the application.
        override func mouseDragged(with event: NSEvent) {
            guard !isDragging,
                  let payload = dragPayload,
                  let start = mouseDownLocation
            else { return }
            let dx = event.locationInWindow.x - start.x
            let dy = event.locationInWindow.y - start.y
            guard dx * dx + dy * dy > Self.clickSlopSquared else { return }

            let item = NSPasteboardItem()
            item.setString(payload, forType: Self.rowType)
            let dragging = NSDraggingItem(pasteboardWriter: item)
            let image = dragImage ?? NSImage(size: bounds.size)
            dragging.setDraggingFrame(bounds, contents: image)
            isDragging = true
            onDragBegin?(payload)
            beginDraggingSession(with: [dragging], event: event, source: self)
        }

        // MARK: - NSDraggingSource

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            // Within the sidebar only: dragging a row onto the Finder must not move anything.
            context == .withinApplication ? .move : []
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            isDragging = false
            mouseDownLocation = nil
            onDragEnd?(operation == .move)
        }

        // MARK: - NSDraggingDestination

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard let payload = payload(from: sender) else { return [] }
            onDragOver?(payload, fraction(of: sender))
            return .move
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard let payload = payload(from: sender) else { return [] }
            onDragOver?(payload, fraction(of: sender))
            return .move
        }

        /// Where in the row the drag is, 0…1 from the top-left corner. Grouping is a *place* inside
        /// a row rather than a length of time spent on it (D103), so the position is the whole
        /// input: without it the model can only guess, and guessing is what made the bar shiver.
        private func fraction(of sender: any NSDraggingInfo) -> CGPoint {
            guard bounds.width > 0, bounds.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
            let point = convert(sender.draggingLocation, from: nil)
            return CGPoint(
                x: min(max(point.x / bounds.width, 0), 1),
                // AppKit's y grows upwards and the bar's rows run downwards.
                y: 1 - min(max(point.y / bounds.height, 0), 1)
            )
        }

        override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            payload(from: sender) != nil
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            guard let payload = payload(from: sender), let onDrop else { return false }
            onDrop(payload)
            return true
        }

        private func payload(from sender: any NSDraggingInfo) -> String? {
            sender.draggingPasteboard.string(forType: Self.rowType)
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
        menu: @escaping () -> [NSMenuItem] = { [] },
        dragPayload: String? = nil,
        dragImage: NSImage? = nil,
        onDrop: ((String) -> Void)? = nil,
        onDragBegin: ((String) -> Void)? = nil,
        onDragOver: ((String, CGPoint) -> Void)? = nil,
        onDragEnd: ((Bool) -> Void)? = nil
    ) -> some View {
        overlay(
            PanelRowInteraction(
                onClick: onClick,
                items: menu,
                dragPayload: dragPayload,
                dragImage: dragImage,
                onDrop: onDrop,
                onDragBegin: onDragBegin,
                onDragOver: onDragOver,
                onDragEnd: onDragEnd
            )
        )
    }
}
