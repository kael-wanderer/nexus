import AppKit

/// The Dock replacement. Never key, never main — the other application's insertion point is
/// never disturbed (D3).
public final class SidebarPanel: NSPanel {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = false
        animationBehavior = .none
        hasShadow = true
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        self.contentView = contentView
    }
}

/// A 2 pt transparent strip on the screen edge whose tracking area reveals a hidden sidebar.
/// Event-driven; no global mouse monitor, no timer, no permission (D4).
public final class EdgeTriggerPanel: NSPanel {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public init(onEnter: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 2, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        contentView = EdgeTriggerView(onEnter: onEnter)
    }
}

final class EdgeTriggerView: NSView {
    private let onEnter: () -> Void
    private var trackingArea: NSTrackingArea?

    init(onEnter: @escaping () -> Void) {
        self.onEnter = onEnter
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter()
    }
}
