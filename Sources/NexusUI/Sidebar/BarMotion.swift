import CoreGraphics
import NexusCore
import SwiftUI

/// What the bar is drawn as inside its window. Pure, so it is tested without a window.
///
/// The window takes its frame in one step — the final one, or the larger of two while a motion
/// is under way — and the bar moves inside it: an animated thickness for hover-expand, an
/// animated offset for auto-hide. Resizing or moving the window on every frame drags its blur and
/// its whole SwiftUI layout along with it.
public struct BarMotion: Equatable, Sendable {
    /// The bar's own thickness: `appearance.width` collapsed, `max(220, appearance.width)`
    /// expanded. Exactly what `SidebarLayout` sizes the window with, so a settled bar fills its
    /// window — including a horizontal bar, which never expands (D53) and whose thickness is
    /// computed to hold its icons.
    public var thickness: CGFloat
    /// How far the bar is pushed toward its screen edge: 0 when revealed, thickness +
    /// screenMargin when hidden. SwiftUI's y grows downward.
    public var offset: CGSize
    /// The window edge the bar is pinned to.
    public var alignment: Alignment

    public static func resolve(
        appearance: AppearanceConfiguration,
        expanded: Bool,
        hidden: Bool
    ) -> BarMotion {
        let thickness = SidebarLayout.width(appearance, expanded: expanded)
        let push = hidden ? thickness + SidebarLayout.screenMargin : 0
        let (offset, alignment): (CGSize, Alignment) = switch appearance.position {
        case .left: (CGSize(width: -push, height: 0), .leading)
        case .right: (CGSize(width: push, height: 0), .trailing)
        case .top: (CGSize(width: 0, height: -push), .top)
        case .bottom: (CGSize(width: 0, height: push), .bottom)
        }
        return BarMotion(thickness: thickness, offset: offset, alignment: alignment)
    }

    /// The window's thickness for a transition between two states: the larger of the two.
    public static func windowExpanded(from: Bool, to: Bool) -> Bool {
        from || to
    }
}
