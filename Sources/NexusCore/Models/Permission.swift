import Foundation

public enum Permission: String, Sendable, Codable, CaseIterable, Hashable {
    case accessibility
    case screenRecording
}

public enum PermissionStatus: String, Sendable, Codable, Hashable {
    case granted
    case denied
    case notDetermined
}

public protocol PermissionChecking: Sendable {
    func status(of permission: Permission) -> PermissionStatus
    /// Only ever called from an explicit user action (§64) — never at launch.
    func requestOrOpenSettings(_ permission: Permission)
    /// 1 Hz while subscribed. The single sanctioned poll (D13): the caller must cancel it when
    /// the permission screen is dismissed.
    func statusStream(for permission: Permission) -> AsyncStream<PermissionStatus>
}
