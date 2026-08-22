import AppKit
import NexusCore

/// The composition root: the only place that builds concrete services and wires them together.
/// Library targets take protocols by injection and never see this type.
@MainActor
final class Composition {
    let events = EventBus()
    let configuration: ConfigurationController

    init() {
        configuration = ConfigurationController(store: ConfigurationStore(), events: events)
    }

    func start() {
        // Materialise the loaded (or default) configuration so it is inspectable with `defaults`
        // from the first launch onwards.
        configuration.flush()
    }

    func statusItemActions() -> StatusItemController.Actions {
        StatusItemController.Actions()
    }

    func shutDown() {
        configuration.flush()
        events.finishAll()
    }
}
