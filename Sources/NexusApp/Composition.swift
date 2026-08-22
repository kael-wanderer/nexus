import AppKit
import NexusCore
import NexusUI

/// The composition root: the only place that builds concrete services and wires them together.
/// Library targets take protocols by injection and never see this type.
@MainActor
final class Composition {
    let events = EventBus()
    let configuration: ConfigurationController
    let permissions: PermissionService
    let applications: ApplicationService
    let applicationMonitor: ApplicationMonitor
    let windows: WindowService
    let windowMonitor: WindowMonitor
    let previews: WindowPreviewService
    let sidebarModel: SidebarViewModel
    let flyoutModel: WindowFlyoutViewModel
    let panels: PanelController

    private var permissionTask: Task<Void, Never>?

    init() {
        configuration = ConfigurationController(store: ConfigurationStore(), events: events)
        permissions = PermissionService(events: events)
        applications = ApplicationService()
        applicationMonitor = ApplicationMonitor(service: applications, events: events)
        windows = WindowService()
        windowMonitor = WindowMonitor(service: windows, events: events)
        previews = WindowPreviewService()
        sidebarModel = SidebarViewModel(
            applications: applications,
            configuration: configuration,
            events: events
        )
        flyoutModel = WindowFlyoutViewModel(
            service: windows,
            previewService: previews,
            permissions: permissions,
            events: events
        )
        panels = PanelController(
            model: sidebarModel,
            flyoutModel: flyoutModel,
            permissions: permissions,
            configuration: configuration,
            events: events
        )
    }

    func start() {
        // Materialise the loaded (or default) configuration so it is inspectable with `defaults`
        // from the first launch onwards.
        configuration.flush()
        sidebarModel.refreshWindowCounts = { [weak self] in self?.applicationMonitor.refresh() }
        sidebarModel.start()
        flyoutModel.start()
        panels.start()
        applicationMonitor.start()
        windowMonitor.start()
        observeAccessibilityGrant()
    }

    /// Accessibility can be granted (or revoked) while Nexus is running. Observers are installed
    /// the moment it is granted and torn down when it is taken away — no restart, no crash (§65).
    private func observeAccessibilityGrant() {
        let stream = events.events()
        permissionTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                guard case .permissionChanged(.accessibility, let status) = event else { continue }
                switch status {
                case .granted:
                    self.windowMonitor.start()
                case .denied, .notDetermined:
                    self.windowMonitor.stop()
                    Log.permissions.info("Accessibility not granted; window features degraded")
                }
            }
        }
    }

    func statusItemActions() -> StatusItemController.Actions {
        StatusItemController.Actions(
            toggleSidebar: { [weak self] in self?.panels.toggleSidebar() }
        )
    }

    func shutDown() {
        permissionTask?.cancel()
        windowMonitor.stop()
        applicationMonitor.stop()
        panels.stop()
        flyoutModel.stop()
        sidebarModel.stop()
        configuration.flush()
        events.finishAll()
    }
}
