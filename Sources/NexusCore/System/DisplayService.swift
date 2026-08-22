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
            return NSScreen.main ?? NSScreen.screens.first
        case .withMouse:
            return screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        case .specific(let uuid):
            if let match = screen(matching: DisplayIdentity(uuid: uuid)) { return match }
            Log.system.info("Preferred display is disconnected; falling back to the main display")
            return NSScreen.main ?? NSScreen.screens.first
        }
    }

    public static func screenContainingMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }
}
