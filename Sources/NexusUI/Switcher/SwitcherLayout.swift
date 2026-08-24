import CoreGraphics
import Foundation

/// The grid's measurements, kept out of the view so the column count can be tested without one.
public enum SwitcherLayout {
    /// Wide enough for a legible thumbnail of a 16:10 screen, narrow enough that four fit across
    /// a 1440-point display.
    public static let cardWidth: CGFloat = 320
    public static let cardHeight: CGFloat = 220
    public static let spacing: CGFloat = 20
    public static let toolbarHeight: CGFloat = 52

    public static func columns(forWidth width: CGFloat, cardWidth: CGFloat, spacing: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        return max(1, Int((width + spacing) / (cardWidth + spacing)))
    }
}
