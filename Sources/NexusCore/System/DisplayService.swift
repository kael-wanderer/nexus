import AppKit
import CoreGraphics
import Foundation

/// Displays are identified by `CGDisplayCreateUUIDFromDisplayID` (D11): `CGDirectDisplayID`
/// changes across disconnect/reconnect, the UUID does not.
@MainActor
public enum DisplayService {
    public static func identity(of screen: NSScreen) -> DisplayIdentity? {
        guard let displayID = displayID(of: screen),
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return nil }
        return DisplayIdentity(uuid: CFUUIDCreateString(nil, uuid) as String)
    }

    public static func screen(matching identity: DisplayIdentity) -> NSScreen? {
        NSScreen.screens.first { Self.identity(of: $0) == identity }
    }

    /// Resolves the configured preference to a real screen. A `.specific` display that is
    /// currently disconnected falls back to the main display, **without** touching the stored
    /// preference — reconnecting restores the sidebar to it.
    public static func screen(for preference: DisplayPreference) -> NSScreen? {
        screens(for: preference).first
    }

    /// Every screen the preference asks for, in order — one, except for `.everyDisplay` (D91).
    /// The menu-bar display comes first there too, so "the primary bar" means the same thing
    /// whatever the preference is.
    public static func screens(for preference: DisplayPreference) -> [NSScreen] {
        if case .everyDisplay = preference {
            let ordered = NSScreen.screens
            return ordered.isEmpty ? [menuBarScreen].compactMap(\.self) : ordered
        }
        return [singleScreen(for: preference)].compactMap(\.self)
    }

    private static func singleScreen(for preference: DisplayPreference) -> NSScreen? {
        switch preference {
        case .everyDisplay, .main:
            return menuBarScreen
        case .withMouse:
            return screenContainingMouse() ?? menuBarScreen
        case .specific(let uuid):
            if let match = screen(matching: DisplayIdentity(uuid: uuid)) { return match }
            Log.system.notice("Preferred display is disconnected; falling back to the main display")
            return menuBarScreen
        }
    }

    /// `NSScreen.main` is the screen containing the **key window**, not the main display — so it
    /// follows Settings or onboarding onto a second monitor and drags the sidebar with it.
    /// `screens.first` is the display with the menu bar, which is what `.main` means here
    /// (design/mvp.md §8).
    public static var menuBarScreen: NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }

    public static func screenContainingMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }

    /// Every display whose **visible** space is a native full-screen one (D111), so the bar on that
    /// display can step aside the way the real Dock does.
    ///
    /// `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` lists only windows on a space that is
    /// currently showing, which is what makes this per-display and not merely per-application: a
    /// full-screen Chrome parked on a space nobody is looking at is not on screen and does not
    /// count. And a full-screen window is the one kind whose frame covers a display *whole* — AppKit
    /// will not put an ordinary window over the menu bar — so the test is a covered display.
    ///
    /// Window bounds are compared against `CGDisplayBounds`, which is in the same flipped space, so
    /// nothing has to be converted. No permission: bounds and layer are readable without Screen
    /// Recording (D5).
    ///
    /// Identified by `CGDirectDisplayID` rather than by UUID (D11) because nothing here is stored:
    /// the set is recomputed whenever the spaces or the displays change, so an id that only lasts as
    /// long as the cable is connected is exactly long enough.
    public static func fullScreenDisplays() -> Set<CGDirectDisplayID> {
        guard let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]]
        else { return [] }

        // Layer 0 is an ordinary document window. Nexus's own panels are `.floating` (layer 3), so
        // the bar can never be mistaken for the application it is covering.
        let windows = info.compactMap { window -> CGRect? in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            return CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
        }
        guard !windows.isEmpty else { return [] }

        var covered: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let displayID = displayID(of: screen) else { continue }
            if isCovered(CGDisplayBounds(displayID), by: windows) { covered.insert(displayID) }
        }
        return covered
    }

    /// Whether one of `windows` covers `display` whole — the test the whole feature rests on, and the
    /// only part of it that can be checked without a second monitor and a hand.
    ///
    /// A point of slack: a display's bounds and its full-screen window's are the same rectangle, but
    /// rounding on a scaled display should not decide a question this coarse. A *maximised* window
    /// stops at the menu bar and so never covers the display, which is exactly the distinction.
    public static func isCovered(_ display: CGRect, by windows: [CGRect]) -> Bool {
        guard display.width > 0, display.height > 0 else { return false }
        return windows.contains { $0.insetBy(dx: -1, dy: -1).contains(display) }
    }

    public static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber
        else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}
