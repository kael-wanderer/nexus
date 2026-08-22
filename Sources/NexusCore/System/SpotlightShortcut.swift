import Foundation

/// Progressive enhancement (review Note 2). macOS stores the Spotlight keyboard shortcut in the
/// `com.apple.symbolichotkeys` defaults domain under `AppleSymbolicHotKeys`, key 64. Reading it
/// needs no permission, but it is undocumented — so `unknown` is a first-class answer and the
/// Spotlight guide falls back to its static text when it comes back.
public enum SpotlightShortcut {
    public enum State: Sendable, Equatable {
        case enabled
        case disabled
        case unknown
    }

    /// 64 = "Show Spotlight search". 65 = "Show Finder search window".
    static let spotlightHotKeyIdentifier = "64"

    public static func state() -> State {
        state(in: CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any])
    }

    /// Split out so the parsing is testable without touching the user's real preferences.
    static func state(in hotKeys: [String: Any]?) -> State {
        guard let hotKeys,
              let entry = hotKeys[spotlightHotKeyIdentifier] as? [String: Any],
              let enabled = entry["enabled"] as? Bool
        else { return .unknown }
        return enabled ? .enabled : .disabled
    }
}
