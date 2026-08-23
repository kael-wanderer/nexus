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
