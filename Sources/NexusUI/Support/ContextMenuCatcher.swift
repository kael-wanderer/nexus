import AppKit
import SwiftUI

/// Event-transparent hover tracking for controls drawn inside non-key panels.
///
/// SwiftUI's `onHover` is tied to whichever rendered layer is under the pointer. That is normally
/// useful, but it makes a hover-only overlay unstable: as soon as the overlay appears it occludes
/// the layer whose hover created it. An AppKit tracking area follows the view's bounds instead, so
/// child overlays can appear without manufacturing a mouse-exit event.
struct PanelHoverRegion: NSViewRepresentable {
    let changed: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(changed: changed)
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.changed = changed
    }

    final class TrackingView: NSView {
        var changed: (Bool) -> Void

        init(changed: @escaping (Bool) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not supported") }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func mouseEntered(with event: NSEvent) { changed(true) }
        override func mouseExited(with event: NSEvent) { changed(false) }
    }
}

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
///    the hit view is one of SwiftUI's internal subviews. The sidebar and the flyout are not key
///    (keyboard mode aside), so *every* click is a first-mouse click — meaning SwiftUI's `.onTapGesture`
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
    /// The drag that started here was let go outside every Nexus window, at that point on screen
    /// (F1, D105).
    var onDragOut: ((NSPoint) -> Void)?
    /// Pressed and held without moving (D107).
    var onLongPress: (() -> Void)?
    /// `true` when the button goes down on the row, `false` when it comes up, a drag starts or a
    /// long press takes over.
    var onPressChange: ((Bool) -> Void)?
    /// A file from outside the bar entered (`true`) or left (`false`) this row.
    var onFileDrag: ((Bool) -> Void)?
    /// Files from outside the bar were dropped on this row; `true` when they were used.
    var onFileDrop: (([URL]) -> Bool)?

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
        view.onDragOut = onDragOut
        view.onLongPress = onLongPress
        view.onPressChange = onPressChange
        view.onFileDrag = onFileDrag
        view.onFileDrop = onFileDrop
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
        var onDragOut: ((NSPoint) -> Void)?
        var onLongPress: (() -> Void)?
        var onPressChange: ((Bool) -> Void)?
        var onFileDrag: ((Bool) -> Void)?
        var onFileDrop: (([URL]) -> Bool)? {
            didSet { registerDropTypes() }
        }

        private var mouseDownLocation: NSPoint?
        private var isDragging = false
        private var longPressTask: Task<Void, Never>?

        /// Squared distance, in points, a press may travel and still count as a click.
        private static let clickSlopSquared: CGFloat = 25

        /// How long a press has to be held, without travelling, to mean "let me edit these" (D107).
        /// The same 600 ms iOS uses, which is long enough not to fire on the way to a drag.
        static let longPress = Duration.milliseconds(600)

        /// The pasteboard type for a row being dragged inside the sidebar. Private to Nexus, so a
        /// stray text drag from another application can never reorder anything.
        static let rowType = NSPasteboard.PasteboardType("com.congbui.nexus.sidebar-row")

        init(onClick: (() -> Void)?, items: @escaping () -> [NSMenuItem]) {
            self.onClick = onClick
            self.items = items
            super.init(frame: .zero)
        }

        private func registerDropTypes() {
            var types: [NSPasteboard.PasteboardType] = []
            if onDrop != nil { types.append(Self.rowType) }
            if onFileDrop != nil { types.append(.fileURL) }
            if types.isEmpty {
                unregisterDraggedTypes()
            } else {
                registerForDraggedTypes(types)
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
            onPressChange?(true)
            guard let onLongPress else { return }
            longPressTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.longPress)
                guard !Task.isCancelled else { return }
                self?.onPressChange?(false)
                onLongPress()
            }
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
            // Travelling means this is a drag, so it is not a long press.
            longPressTask?.cancel()
            longPressTask = nil
            onPressChange?(false)

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
            if operation == .move {
                onDragEnd?(true)
                return
            }
            // Nothing took the drop. Off Nexus altogether is the Dock's "drag it off" gesture
            // (D105); anywhere else — a Nexus panel that refused it — is a cancel.
            if let onDragOut, !Self.isOverNexus(screenPoint) {
                onDragOut(screenPoint)
                return
            }
            onDragEnd?(false)
        }

        /// Whether a screen point is over any window Nexus has on screen. The bar's own frame is not
        /// enough: the group popover and the folder stack are separate windows, and letting go over
        /// one of those must not throw the row off the bar.
        private static func isOverNexus(_ screenPoint: NSPoint) -> Bool {
            NSApp.windows.contains { $0.isVisible && $0.frame.contains(screenPoint) }
        }

        // MARK: - NSDraggingDestination

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            if let payload = payload(from: sender) {
                onDragOver?(payload, fraction(of: sender))
                return .move
            }
            return fileDragOperation(sender)
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            if let payload = payload(from: sender) {
                onDragOver?(payload, fraction(of: sender))
                return .move
            }
            return fileDragOperation(sender)
        }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) {
            onFileDrag?(false)
        }

        override func draggingEnded(_ sender: any NSDraggingInfo) {
            onFileDrag?(false)
        }

        /// A pasteboard of files, for a row that opens them. Rows' own drags are handled first.
        private func fileDragOperation(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard onFileDrop != nil, !fileURLs(from: sender).isEmpty else { return [] }
            onFileDrag?(true)
            return .copy
        }

        private func fileURLs(from sender: any NSDraggingInfo) -> [URL] {
            let objects = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            )
            return (objects as? [URL]) ?? []
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
            payload(from: sender) != nil || (onFileDrop != nil && !fileURLs(from: sender).isEmpty)
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            if payload(from: sender) == nil, let onFileDrop {
                onFileDrag?(false)
                return onFileDrop(fileURLs(from: sender))
            }
            guard let payload = payload(from: sender), let onDrop else { return false }
            onDrop(payload)
            return true
        }

        private func payload(from sender: any NSDraggingInfo) -> String? {
            sender.draggingPasteboard.string(forType: Self.rowType)
        }

        override func mouseUp(with event: NSEvent) {
            defer { mouseDownLocation = nil }
            onPressChange?(false)
            longPressTask?.cancel()
            longPressTask = nil
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
        onDragEnd: ((Bool) -> Void)? = nil,
        onDragOut: ((NSPoint) -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        onPressChange: ((Bool) -> Void)? = nil,
        onFileDrag: ((Bool) -> Void)? = nil,
        onFileDrop: (([URL]) -> Bool)? = nil
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
                onDragEnd: onDragEnd,
                onDragOut: onDragOut,
                onLongPress: onLongPress,
                onPressChange: onPressChange,
                onFileDrag: onFileDrag,
                onFileDrop: onFileDrop
            )
        )
    }
}
