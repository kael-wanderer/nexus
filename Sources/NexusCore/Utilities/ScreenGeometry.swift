import AppKit
import CoreGraphics
import Foundation

/// The two screen coordinate spaces macOS uses, and the one line that converts between them.
///
/// Cocoa (`NSScreen`, `NSWindow`) measures upwards from the bottom-left of the primary display;
/// Accessibility and `CGWindowList` measure downwards from its top-left. Anything that reads a
/// window's frame and compares it to a panel's frame has to pick one space and convert.
public enum ScreenGeometry {
    /// Flips a rectangle between the two spaces. Its own inverse.
    public static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Height of the display the coordinate spaces are anchored to — the one with the menu bar,
    /// whose Cocoa origin is `(0, 0)`.
    @MainActor
    public static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
    }
}
