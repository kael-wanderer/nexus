import AppKit
import SwiftUI

/// Shared metrics and motion rules. System materials and semantic colors only, so dark mode,
/// light mode and Increase Contrast come for free (§9 of docs/design/mvp.md).
public enum Design {
    public static let itemCornerRadius: CGFloat = 10

    /// The ring drawn around the row the keyboard is on (M23). Two points, tinted, so it reads at
    /// a glance on a busy bar — and it is a shape the hover highlight never draws, so the two are
    /// not told apart by colour alone.
    public static let focusRingWidth: CGFloat = 2
    public static let sectionSpacing: CGFloat = 8
    public static let separatorHeight: CGFloat = 1
    public static let runningDotDiameter: CGFloat = 4

    /// Every animation is gated on Reduce Motion at the call site.
    public static func animation(_ base: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }

    /// The bar's own motion: hover-expand and auto-hide. A spring with no bounce, so an
    /// interrupted motion turns around from where it is with the speed it has.
    public static let reveal = Animation.spring(duration: 0.26, bounce: 0)
    public static let hover = Animation.easeOut(duration: 0.12)

    /// An icon under the pointer's press shrinks to `pressScale` and springs back on release.
    public static let press = Animation.spring(duration: 0.18, bounce: 0)
    public static let pressScale: CGFloat = 0.92

    /// One launch hop is `hopUp` then `hopDown`, 400 ms in all; it repeats while the launch lasts.
    public static let hopUp = Animation.easeOut(duration: 0.20)
    public static let hopDown = Animation.easeIn(duration: 0.20)

    /// How long the bar is left alone after a hover-expand starts, so the refreshes it triggers
    /// do not rebuild the rows while they are still moving.
    public static let settleDelay: Duration = .milliseconds(300)
}

extension Design {
    /// Where to put a window so it opens on the screen the pointer is on, rather than wherever
    /// AppKit would centre it. Used by the alerts the bar raises: a rename asked for on the second
    /// monitor has no business appearing on the first (D102).
    @MainActor
    public static func centred(_ size: CGSize, onScreenUnder point: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else {
            return CGRect(origin: .zero, size: size)
        }
        return CGRect(
            x: frame.midX - size.width / 2,
            // A touch above centre, which is where macOS puts its own alerts.
            y: frame.midY - size.height / 2 + frame.height * 0.1,
            width: size.width,
            height: size.height
        )
    }
}
