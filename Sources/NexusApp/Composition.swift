import AppKit
import NexusCore
import NexusUI

/// The composition root: the only place that builds concrete services and wires them together.
/// Library targets take protocols by injection and never see this type.
@MainActor
final class Composition {
    let events = EventBus()
    let configuration: ConfigurationController
    let applications: ApplicationService
    let sidebarModel: SidebarViewModel
    let panels: PanelController

    init() {
        configuration = ConfigurationController(store: ConfigurationStore(), events: events)
        applications = ApplicationService()
        sidebarModel = SidebarViewModel(
            applications: applications,
            configuration: configuration,
            events: events
        )
        panels = PanelController(
            model: sidebarModel,
            configuration: configuration,
            events: events
        )
    }

    func start() {
        // Materialise the loaded (or default) configuration so it is inspectable with `defaults`
        // from the first launch onwards.
        configuration.flush()
        sidebarModel.start()
        panels.start()
    }

    func statusItemActions() -> StatusItemController.Actions {
        StatusItemController.Actions(
            toggleSidebar: { [weak self] in self?.panels.toggleSidebar() }
        )
    }

    func shutDown() {
        panels.stop()
        sidebarModel.stop()
        configuration.flush()
        events.finishAll()
    }
}
