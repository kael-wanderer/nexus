import Foundation
import ServiceManagement

/// Launch at login via `SMAppService.mainApp` (macOS 13+). No helper bundle, no login-item
/// shim — the user sees and controls it in System Settings > General > Login Items.
@MainActor
public enum LoginItemService {
    public enum State: Sendable, Equatable {
        case enabled
        case disabled
        /// The user turned it off in System Settings, or macOS has not registered it yet.
        case requiresApproval
        case unavailable
    }

    public static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    public static var isEnabled: Bool { state == .enabled }

    /// Throws rather than silently disagreeing with the toggle: the caller re-reads `state` and
    /// shows what macOS actually did.
    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        Log.system.notice("Launch at login set to \(enabled, privacy: .public); state is now \(String(describing: state), privacy: .public)")
    }
}
