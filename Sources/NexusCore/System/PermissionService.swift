import AppKit
import CoreGraphics
import Foundation

/// Permissions as capabilities (§64). The UI asks this service and never the macOS API.
public final class PermissionService: PermissionChecking, Sendable {
    private let events: EventBus

    public init(events: EventBus) {
        self.events = events
    }

    public func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .accessibility:
            return AX.isTrusted ? .granted : .denied
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        }
    }

    /// Explicit user action only. Shows the system prompt once, then opens the right System
    /// Settings pane — macOS shows its prompt at most once per app signature, so the deep link
    /// is what actually helps on the second attempt.
    public func requestOrOpenSettings(_ permission: Permission) {
        switch permission {
        case .accessibility:
            _ = AX.promptForTrust()
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
        openSettings(for: permission)
    }

    public func openSettings(for permission: Permission) {
        guard let url = URL(string: Self.settingsURL(for: permission)) else { return }
        Log.permissions.info("Opening System Settings for \(permission.rawValue, privacy: .public)")
        NSWorkspace.shared.open(url)
    }

    public static func settingsURL(for permission: Permission) -> String {
        switch permission {
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
    }

    /// The single sanctioned poll (D13): macOS publishes no TCC change notification. 1 Hz, and
    /// it stops the moment the consumer stops iterating — which the permission screens do when
    /// they are dismissed.
    public func statusStream(for permission: Permission) -> AsyncStream<PermissionStatus> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                var previous: PermissionStatus?
                while !Task.isCancelled {
                    guard let self else { break }
                    let current = self.status(of: permission)
                    if current != previous {
                        previous = current
                        continuation.yield(current)
                        self.events.publish(.permissionChanged(permission, current))
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
