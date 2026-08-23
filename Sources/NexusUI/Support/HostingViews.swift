import AppKit
import NexusCore
import SwiftUI

/// A non-key panel normally swallows the first click into it. Accepting first mouse is what
/// makes the sidebar act immediately without a click-to-focus step (design/mvp.md §2.1).
public final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    required public init(rootView: Content) {
        super.init(rootView: rootView)
    }
}

/// The bar's own hosting view: the first-mouse rule, and the drop target for files dragged from
/// Finder. Keys are the panel's business (D101), not this view's.
public final class BarHostingView<Content: View>: NSHostingView<Content> {
    /// A drop from Finder — an application to pin, or a folder to keep as a stack (M21). Handled
    /// in AppKit rather than with SwiftUI's `.dropDestination`, for the same reason clicks are
    /// (D39): the row overlays sit on top of the SwiftUI view and a drop over one of them never
    /// reached it. They register only Nexus's own row type, so a file drag falls through to here.
    public var onFiles: (([URL]) -> Bool)?

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    required public init(rootView: Content) {
        super.init(rootView: rootView)
        // The bar's own rows as well as files: a row let go anywhere inside the bar is a drop, not
        // a cancel (D103). The rows' own catchers sit deeper in the hierarchy, so they still take
        // the drops that land on a row; this one takes the gaps, the padding and the end of the
        // section, which used to revert the whole drag.
        registerForDraggedTypes([.fileURL, PanelRowInteraction.CatcherView.rowType])
    }

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        operation(for: sender)
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        operation(for: sender)
    }

    private func operation(for sender: any NSDraggingInfo) -> NSDragOperation {
        if Self.isRow(sender) { return .move }
        return Self.urls(from: sender).isEmpty ? [] : .copy
    }

    /// A row dropped on the bar needs no handling beyond saying yes: the drag's source commits the
    /// preview it has been maintaining all along, when it hears the operation was `.move`.
    static func isRow(_ sender: any NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.availableType(
            from: [PanelRowInteraction.CatcherView.rowType]
        ) != nil
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if Self.isRow(sender) { return true }
        let urls = Self.urls(from: sender)
        guard !urls.isEmpty else { return false }
        let accepted = onFiles?(urls) ?? false
        Log.sidebar.notice(
            "Dropped \(urls.count, privacy: .public) file(s) on the bar: \(accepted ? "pinned" : "nothing to pin", privacy: .public)"
        )
        return accepted
    }

    static func urls(from sender: any NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

}

/// System material background. Semantic materials mean dark mode, light mode and Increase
/// Contrast all come for free.
public struct VisualEffectBackground: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blending: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blending: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blending = blending
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// A key press that means something to the bar in keyboard mode (M23). Both axes map to the same
/// two commands: the rows run along the bar, so `→` on a bottom bar means what `↓` means on a left
/// one.
public enum BarKeyCommand: Sendable, Equatable {
    case previous
    case next
    case first
    case last
    case activate
    case cancel

    public init?(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case 123, 126: self = .previous          // ← ↑
        case 124, 125: self = .next              // → ↓
        case 115: self = .first                  // Home
        case 119: self = .last                   // End
        case 36, 76, 49: self = .activate        // Return, Enter, Space
        case 53: self = .cancel                  // Escape
        default: return nil
        }
    }
}

extension View {
    /// Marks the row the keyboard is on (M23).
    public func nexusFocusRing(_ isFocused: Bool) -> some View {
        overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                    .strokeBorder(.tint, lineWidth: Design.focusRingWidth)
            }
        }
    }
}
