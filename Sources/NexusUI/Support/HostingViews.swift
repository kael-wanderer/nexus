import AppKit
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

/// The bar's own hosting view. Same first-mouse rule, plus the keys that drive keyboard mode
/// (M23) — handled here rather than in SwiftUI because the panel is only key while the user has
/// asked for it, and `onKeyPress` in a window that is usually not key is not a thing to rely on.
public final class BarHostingView<Content: View>: NSHostingView<Content> {
    /// Set by `PanelController`. Returning `true` means the key was used and must not travel on.
    public var onKey: ((KeyCommand) -> Bool)?

    public enum KeyCommand: Sendable, Equatable {
        case previous
        case next
        case first
        case last
        case activate
        case cancel
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    required public init(rootView: Content) {
        super.init(rootView: rootView)
    }

    public override func keyDown(with event: NSEvent) {
        guard let command = Self.command(for: event), onKey?(command) == true else {
            super.keyDown(with: event)
            return
        }
    }

    /// Both axes are accepted whichever edge the bar is on: the rows run along the bar, and a
    /// person pressing → on a bottom bar means the same thing as ↓ on a left one.
    public static func command(for event: NSEvent) -> KeyCommand? {
        switch Int(event.keyCode) {
        case 123, 126: return .previous          // ← ↑
        case 124, 125: return .next              // → ↓
        case 115: return .first                  // Home
        case 119: return .last                   // End
        case 36, 76, 49: return .activate        // Return, Enter, Space
        case 53: return .cancel                  // Escape
        default: return nil
        }
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
