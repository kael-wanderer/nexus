import AppKit
import CoreGraphics
import Foundation

/// Displays are identified by `CGDisplayCreateUUIDFromDisplayID` (D11): `CGDirectDisplayID`
/// changes across disconnect/reconnect, the UUID does not.
@MainActor
public enum DisplayService {
    public static func identity(of screen: NSScreen) -> DisplayIdentity? {
        guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return DisplayIdentity(uuid: CFUUIDCreateString(nil, uuid) as String)
    }

    public static func screen(matching identity: DisplayIdentity) -> NSScreen? {
        NSScreen.screens.first { Self.identity(of: $0) == identity }
    }

    /// Resolves the configured preference to a real screen. A `.specific` display that is
    /// currently disconnected falls back to the main display, **without** touching the stored
    /// preference — reconnecting restores the sidebar to it.
    public static func screen(for preference: DisplayPreference) -> NSScreen? {
        switch preference {
        case .main:
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
    /// (DESIGN_MVP §8).
    public static var menuBarScreen: NSScreen? {
        NSScreen.screens.first ?? NSScreen.main
    }

    public static func screenContainingMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }
}
