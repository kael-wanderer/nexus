import CoreGraphics
import NexusCore

/// Where the start menu panel sits. Pure, so all four corners are unit-tested rather than
/// eyeballed on one display.
public enum StartMenuLayout {
    public static let margin: CGFloat = 8

    public static func frame(
        size: CGSize,
        in visibleFrame: CGRect,
        corner: StartMenuCorner
    ) -> CGRect {
        // Clamp first: a panel taller than the display must not be positioned off it.
        let width = min(size.width, visibleFrame.width - margin * 2)
        let height = min(size.height, visibleFrame.height - margin * 2)

        let x: CGFloat = switch corner {
        case .bottomLeading, .topLeading: visibleFrame.minX + margin
        case .bottomTrailing, .topTrailing: visibleFrame.maxX - width - margin
        }
        let y: CGFloat = switch corner {
        case .bottomLeading, .bottomTrailing: visibleFrame.minY + margin
        case .topLeading, .topTrailing: visibleFrame.maxY - height - margin
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The corner nearest the sidebar, used as the default so the button and the panel it opens
    /// are on the same side of the screen.
    public static func defaultCorner(for position: SidebarPosition) -> StartMenuCorner {
        switch position {
        case .left, .bottom: .bottomLeading
        case .right: .bottomTrailing
        case .top: .topLeading
        }
    }
}
