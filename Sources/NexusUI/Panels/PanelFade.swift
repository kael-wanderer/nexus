import AppKit

/// Fades a popover panel in and out. The window server animates the window's alpha, so no view is
/// laid out per frame.
///
/// A hide is not finished when `hide` returns: the panel stays on screen until the fade ends. Code
/// that needs to know whether a popover is open must ask its model, not `panel.isVisible`.
@MainActor
public final class PanelFade {
    public static let fadeIn: TimeInterval = 0.12
    public static let fadeOut: TimeInterval = 0.09

    private let reduceMotion: () -> Bool
    /// Bumped by every show and hide of a panel. A hide's completion orders the panel out only if
    /// nothing has been shown or hidden since, so "hide, show 50 ms later" cannot lose the panel.
    private var generations: [ObjectIdentifier: Int] = [:]

    public init(reduceMotion: @escaping () -> Bool) {
        self.reduceMotion = reduceMotion
    }

    private func bump(_ panel: NSPanel) -> Int {
        let key = ObjectIdentifier(panel)
        let next = (generations[key] ?? 0) + 1
        generations[key] = next
        return next
    }

    public func show(_ panel: NSPanel) {
        _ = bump(panel)
        if reduceMotion() {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeIn
            panel.animator().alphaValue = 1
        }
    }

    public func hide(_ panel: NSPanel) {
        let generation = bump(panel)
        if reduceMotion() {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        guard panel.isVisible else {
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOut
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                guard let self, let panel,
                      self.generations[ObjectIdentifier(panel)] == generation else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }
}
