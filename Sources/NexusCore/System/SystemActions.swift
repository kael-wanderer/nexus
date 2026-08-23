import AppKit
import Foundation

/// Sleep, restart, shut down, log out — the row at the foot of the start menu.
///
/// All four go through System Events, the same Automation path Empty Trash uses (D57): macOS
/// exposes no public API for them, and a refusal leaves the machine alone and is logged.
public enum SystemAction: String, CaseIterable, Sendable {
    case sleep
    case restart
    case shutDown
    case logOut

    public var title: String {
        switch self {
        case .sleep: String(localized: "Sleep")
        case .restart: String(localized: "Restart…")
        case .shutDown: String(localized: "Shut Down…")
        case .logOut: String(localized: "Log Out…")
        }
    }

    public var symbolName: String {
        switch self {
        case .sleep: "moon"
        case .restart: "arrow.clockwise"
        case .shutDown: "power"
        case .logOut: "rectangle.portrait.and.arrow.right"
        }
    }

    /// Everything except sleep ends the session, so everything except sleep asks first.
    public var needsConfirmation: Bool { self != .sleep }

    var script: String {
        switch self {
        case .sleep: "tell application \"System Events\" to sleep"
        case .restart: "tell application \"System Events\" to restart"
        case .shutDown: "tell application \"System Events\" to shut down"
        case .logOut: "tell application \"System Events\" to log out"
        }
    }
}

public enum SystemActions {
    @discardableResult
    public static func run(_ action: SystemAction) -> Bool {
        guard let script = NSAppleScript(source: action.script) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            Log.system.error(
                "\(action.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)"
            )
            return false
        }
        Log.system.notice("Ran \(action.rawValue, privacy: .public)")
        return true
    }
}
