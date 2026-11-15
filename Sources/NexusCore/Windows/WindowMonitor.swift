import AppKit
import ApplicationServices
import Foundation

/// Carries a plain closure across the C callback boundary. Holds nothing mutable.
private final class AXCallbackBox: @unchecked Sendable {
    let notify: @Sendable (String) -> Void
    init(notify: @escaping @Sendable (String) -> Void) { self.notify = notify }
}

private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    Unmanaged<AXCallbackBox>.fromOpaque(refcon).takeUnretainedValue().notify(notification as String)
}

/// One `AXObserver` per running application, created when the application appears and destroyed
/// when it terminates. Push only; the only "timer" is an 80 ms coalescing delay so a burst of
/// title changes while the user types becomes one refresh.
@MainActor
public final class WindowMonitor {
    private static let notifications: [String] = [
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXTitleChangedNotification,
        kAXFocusedWindowChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    /// Moves and resizes. Installed only while something acts on them (M12): dragging one window
    /// emits hundreds of these, and every one of them wakes the main run loop.
    private static let geometryNotifications: [String] = [
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
    ]

    private struct Registration {
        let observer: AXObserver
        let box: AXCallbackBox
    }

    private let service: WindowService
    private let events: EventBus
    private var registrations: [ApplicationIdentity: Registration] = [:]
    private var coalescing: [ApplicationIdentity: Task<Void, Never>] = [:]
    private var geometryCoalescing: [ApplicationIdentity: Task<Void, Never>] = [:]
    /// Pending second attempts for applications that were not ready to be observed.
    private var registrationRetries: [ApplicationIdentity: Task<Void, Never>] = [:]
    /// An application that has only just launched often answers "cannot complete". Three more
    /// tries, a little further apart each time, and then it is left alone — a bounded retry, not
    /// a poll.
    private static let registrationRetryDelays: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2)]
    private var eventTask: Task<Void, Never>?
    private var isRunning = false
    private var observesGeometry = false

    public init(service: WindowService, events: EventBus) {
        self.service = service
        self.events = events
    }

    /// Idempotent. Does nothing while Accessibility is denied, and is safe to call again the
    /// moment it is granted.
    public func start() {
        guard AX.isTrusted else {
            Log.windows.notice("Accessibility not granted; window observers not installed")
            return
        }
        guard !isRunning else { return }
        isRunning = true

        for identity in Self.regularApplications() { register(identity) }

        let stream = events.events()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .applicationLaunched(let identity):
                    self.register(identity)
                case .applicationTerminated(let identity):
                    self.unregister(identity)
                    await self.service.forget(identity)
                case .permissionChanged(.accessibility, .denied):
                    self.stop()
                default:
                    continue
                }
            }
        }
        Log.windows.notice("Window observers installed for \(self.registrations.count, privacy: .public) applications")
    }

    public func stop() {
        isRunning = false
        eventTask?.cancel()
        eventTask = nil
        for task in coalescing.values { task.cancel() }
        coalescing.removeAll()
        for task in geometryCoalescing.values { task.cancel() }
        geometryCoalescing.removeAll()
        for task in registrationRetries.values { task.cancel() }
        registrationRetries.removeAll()
        for identity in registrations.keys { unregister(identity) }
    }

    // MARK: - Registration

    private func register(_ identity: ApplicationIdentity, attempt: Int = 0) {
        guard isRunning, registrations[identity] == nil else { return }
        guard let pid = identity.processIdentifier ?? Self.processIdentifier(for: identity) else { return }
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &observer) == .success,
              let observer
        else {
            Log.windows.debug("Could not create an AX observer for \(identity.bundleIdentifier, privacy: .public)")
            return
        }

        let box = AXCallbackBox { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Self.geometryNotifications.contains(notification) {
                    self.scheduleGeometryRefresh(identity)
                } else {
                    self.scheduleRefresh(identity)
                }
            }
        }
        let refcon = Unmanaged.passUnretained(box).toOpaque()
        let element = AX.application(pid: pid)
        // "Cannot complete" means the application did not answer, not that it never will. Any
        // other refusal — unsupported, already registered — is final and not worth retrying.
        var wasNotReady = false
        for notification in Self.notifications {
            let status = AXObserverAddNotification(observer, element, notification as CFString, refcon)
            if status == .cannotComplete { wasNotReady = true }
        }
        if observesGeometry {
            for notification in Self.geometryNotifications {
                let status = AXObserverAddNotification(observer, element, notification as CFString, refcon)
                if status == .cannotComplete { wasNotReady = true }
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        registrations[identity] = Registration(observer: observer, box: box)

        guard wasNotReady, attempt < Self.registrationRetryDelays.count else { return }
        Log.windows.debug("\(identity.bundleIdentifier, privacy: .public) was not ready to be observed; retrying")
        let delay = Self.registrationRetryDelays[attempt]
        registrationRetries[identity]?.cancel()
        registrationRetries[identity] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.registrationRetries[identity] = nil
            // Start again from nothing: a half-registered observer would otherwise be kept, and
            // the `registrations` guard above would turn the retry away.
            self.unregister(identity)
            self.register(identity, attempt: attempt + 1)
        }
    }

    /// Starts or stops listening for window moves and resizes, on the observers that already
    /// exist. Idempotent.
    public func setObservesGeometry(_ observes: Bool) {
        guard observes != observesGeometry else { return }
        observesGeometry = observes
        for (identity, registration) in registrations {
            guard let pid = identity.processIdentifier ?? Self.processIdentifier(for: identity)
            else { continue }
            let element = AX.application(pid: pid)
            let refcon = Unmanaged.passUnretained(registration.box).toOpaque()
            for notification in Self.geometryNotifications {
                if observes {
                    AXObserverAddNotification(registration.observer, element, notification as CFString, refcon)
                } else {
                    AXObserverRemoveNotification(registration.observer, element, notification as CFString)
                }
            }
        }
        if !observes {
            for task in geometryCoalescing.values { task.cancel() }
            geometryCoalescing.removeAll()
        }
        Log.windows.notice("Window geometry observers \(observes ? "installed" : "removed", privacy: .public)")
    }

    private func unregister(_ identity: ApplicationIdentity) {
        guard let registration = registrations.removeValue(forKey: identity) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(registration.observer),
            .defaultMode
        )
        coalescing.removeValue(forKey: identity)?.cancel()
        geometryCoalescing.removeValue(forKey: identity)?.cancel()
        registrationRetries.removeValue(forKey: identity)?.cancel()
    }

    private func scheduleRefresh(_ identity: ApplicationIdentity) {
        coalescing[identity]?.cancel()
        coalescing[identity] = Task { [weak self, events] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            events.publish(.windowsChanged(identity))
            self?.coalescing[identity] = nil
        }
    }

    /// Waits for the moving to stop rather than coalescing a burst: acting mid-drag would fight
    /// the drag, so the event fires once the window has been still for a moment.
    private func scheduleGeometryRefresh(_ identity: ApplicationIdentity) {
        geometryCoalescing[identity]?.cancel()
        geometryCoalescing[identity] = Task { [weak self, events] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            events.publish(.windowGeometrySettled(identity))
            self?.geometryCoalescing[identity] = nil
        }
    }

    private static func processIdentifier(for identity: ApplicationIdentity) -> pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: identity.bundleIdentifier)
            .first?
            .processIdentifier
    }

    private static func regularApplications() -> [ApplicationIdentity] {
        NSWorkspace.shared.runningApplications.compactMap { running in
            guard running.activationPolicy == .regular,
                  let bundleIdentifier = running.bundleIdentifier
            else { return nil }
            return ApplicationIdentity(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: running.processIdentifier
            )
        }
    }
}
