import Foundation

public enum NexusEvent: Sendable, Equatable {
    case applicationLaunched(ApplicationIdentity)
    case applicationTerminated(ApplicationIdentity)
    case applicationActivated(ApplicationIdentity)
    case applicationsChanged
    /// One coalesced event per application whose window layer changed — created, closed,
    /// retitled, minimised or focused. Consumers re-read the authoritative list from
    /// `WindowService` (D22).
    case windowsChanged(ApplicationIdentity)
    /// One coalesced event per application whose windows stopped moving or resizing. Separate from
    /// `windowsChanged` because it fires continuously while a window is dragged, and only Reserved
    /// Space (M12) cares — the observers for it are installed only while that setting is on.
    case windowGeometrySettled(ApplicationIdentity)
    case displaysChanged
    case configurationChanged(NexusConfiguration)
    case permissionChanged(Permission, PermissionStatus)
}

/// Typed multicast over `AsyncStream` (D12). Subscribers get their own buffered stream; a slow
/// consumer drops events rather than back-pressuring the producer, and re-reads authoritative
/// state from the service on wake.
public final class EventBus: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuations: [UUID: AsyncStream<NexusEvent>.Continuation] = [:]

    public init() {}

    public func publish(_ event: NexusEvent) {
        lock.lock()
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets { continuation.yield(event) }
    }

    public func events() -> AsyncStream<NexusEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<NexusEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        continuation.onTermination = { [weak self] _ in self?.remove(id) }
        lock.lock()
        continuations[id] = continuation
        lock.unlock()
        return stream
    }

    /// Test/teardown helper: finishes every live subscription.
    public func finishAll() {
        lock.lock()
        let targets = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for continuation in targets { continuation.finish() }
    }

    public var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }
}
