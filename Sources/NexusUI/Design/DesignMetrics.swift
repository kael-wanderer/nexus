import SwiftUI

/// Shared metrics and motion rules. System materials and semantic colors only, so dark mode,
/// light mode and Increase Contrast come for free (§9 of design/mvp.md).
public enum Design {
    public static let itemCornerRadius: CGFloat = 10
    public static let sidebarInset: CGFloat = 6
    public static let sectionSpacing: CGFloat = 8
    public static let separatorHeight: CGFloat = 1
    public static let runningDotDiameter: CGFloat = 4

    /// Every animation is gated on Reduce Motion at the call site.
    public static func animation(_ base: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }

    public static let reveal = Animation.easeOut(duration: 0.18)
    public static let hover = Animation.easeOut(duration: 0.12)
}
