import AppKit
import Foundation

/// Translates `NSWorkspace` notifications into `NexusEvent`s. Push only — no timer, no polling
/// (§18, D13).
@MainActor
public final class ApplicationMonitor {
    private let service: ApplicationService
    private let events: EventBus
    private var observers: [any NSObjectProtocol] = []

    public init(service: ApplicationService, events: EventBus) {
        self.service = service
        self.events = events
    }

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.didLaunchApplicationNotification) { [weak self] identity in
            self?.events.publish(.applicationLaunched(identity))
            self?.refresh()
        }
        observe(center, NSWorkspace.didTerminateApplicationNotification) { [weak self] identity in
            self?.events.publish(.applicationTerminated(identity))
            self?.refresh()
        }
        observe(center, NSWorkspace.didActivateApplicationNotification) { [weak self] identity in
            guard let self else { return }
            let bundleIdentifier = identity.bundleIdentifier
            Task { await self.service.updateActiveApplication(bundleIdentifier) }
            self.events.publish(.applicationActivated(identity))
            self.refresh()
        }
        refresh()
        Log.applications.info("Application monitor started")
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    /// Recomputes window counts and republishes. Called on every application event and whenever
    /// the user's pointer enters the sidebar — macOS publishes no notification for a window
    /// opening in another app until Accessibility observers arrive at Milestone 4.
    public func refresh() {
        let counts = WindowCounts.byProcess()
        Task { [service, events] in
            await service.updateWindowCounts(counts)
            events.publish(.applicationsChanged)
        }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ handler: @escaping @MainActor (ApplicationIdentity) -> Void
    ) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            // Reduce the non-`Sendable` NSRunningApplication to a value type before hopping.
            guard
                let running = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                let bundleIdentifier = running.bundleIdentifier
            else { return }
            let identity = ApplicationIdentity(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: running.processIdentifier
            )
            MainActor.assumeIsolated { handler(identity) }
        }
        observers.append(observer)
    }
}
