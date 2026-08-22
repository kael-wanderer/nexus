import CoreGraphics
import Foundation

/// Persisted form is the bundle identifier alone — `pid_t` is not stable across relaunch.
public struct ApplicationIdentity: Hashable, Sendable, Codable {
    public let bundleIdentifier: String
    public let processIdentifier: pid_t?

    public init(bundleIdentifier: String, processIdentifier: pid_t? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }

    /// Identity comparison ignores the pid: the same app before and after relaunch is the same app.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }
}

public struct WindowIdentity: Hashable, Sendable {
    public let owner: ApplicationIdentity
    public let number: CGWindowID

    public init(owner: ApplicationIdentity, number: CGWindowID) {
        self.owner = owner
        self.number = number
    }
}

/// `CGDirectDisplayID` is not stable across disconnect/reconnect; the UUID is (D11).
public struct DisplayIdentity: Hashable, Sendable, Codable {
    public let uuid: String
    public init(uuid: String) { self.uuid = uuid }
}
