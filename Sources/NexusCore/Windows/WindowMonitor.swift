import AppKit
import ApplicationServices
import Foundation

/// Carries a plain closure across the C callback boundary. Holds nothing mutable.
private final class AXCallbackBox: @unchecked Sendable {
    let notify: @Sendable () -> Void
    init(notify: @escaping @Sendable () -> Void) { self.notify = notify }
}

private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    Unmanaged<AXCallbackBox>.fromOpaque(refcon).takeUnretainedValue().notify()
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

    private struct Registration {
        let observer: AXObserver
        let box: AXCallbackBox
    }

    private let service: WindowService
    private let events: EventBus
    private var registrations: [ApplicationIdentity: Registration] = [:]
    private var coalescing: [ApplicationIdentity: Task<Void, Never>] = [:]
    private var eventTask: Task<Void, Never>?
    private var isRunning = false

    public init(service: WindowService, events: EventBus) {
        self.service = service
        self.events = events
    }

    /// Idempotent. Does nothing while Accessibility is denied, and is safe to call again the
    /// moment it is granted.
    public func start() {
        guard AX.isTrusted else {
            Log.windows.info("Accessibility not granted; window observers not installed")
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
        Log.windows.info("Window observers installed for \(self.registrations.count, privacy: .public) applications")
    }

    public func stop() {
        isRunning = false
        eventTask?.cancel()
        eventTask = nil
        for task in coalescing.values { task.cancel() }
        coalescing.removeAll()
        for identity in registrations.keys { unregister(identity) }
    }

    // MARK: - Registration

    private func register(_ identity: ApplicationIdentity) {
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

        let box = AXCallbackBox { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRefresh(identity) }
        }
        let refcon = Unmanaged.passUnretained(box).toOpaque()
        let element = AX.application(pid: pid)
        for notification in Self.notifications {
            AXObserverAddNotification(observer, element, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        registrations[identity] = Registration(observer: observer, box: box)
    }

    private func unregister(_ identity: ApplicationIdentity) {
        guard let registration = registrations.removeValue(forKey: identity) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(registration.observer),
            .defaultMode
        )
        coalescing.removeValue(forKey: identity)?.cancel()
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
