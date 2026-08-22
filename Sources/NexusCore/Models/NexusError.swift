import Foundation

public enum NexusError: Error, Sendable, Equatable {
    case permissionDenied(Permission)
    case targetDisappeared
    case systemDenied(Int32)
    case timedOut
    case notFound
}
