import Foundation

/// Owns the live configuration. Every mutation goes through `update`, which publishes
/// `.configurationChanged` immediately (so the UI applies live) and writes to the store
/// debounced by 250 ms (so dragging a slider is not a write storm).
@MainActor
@Observable
public final class ConfigurationController {
    public private(set) var configuration: NexusConfiguration

    @ObservationIgnored private let store: any ConfigurationStoring
    @ObservationIgnored private let events: EventBus
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public init(
        store: any ConfigurationStoring,
        events: EventBus,
        saveDelay: Duration = .milliseconds(250)
    ) {
        self.store = store
        self.events = events
        self.saveDelay = saveDelay
        self.configuration = store.load()
    }

    public func update(_ mutate: (inout NexusConfiguration) -> Void) {
        var next = configuration
        mutate(&next)
        next.appearance.clamp()
        guard next != configuration else { return }
        configuration = next
        events.publish(.configurationChanged(next))
        scheduleSave()
    }

    /// Writes any pending change synchronously. Called on terminate.
    public func flush() {
        saveTask?.cancel()
        saveTask = nil
        write()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            self.write()
        }
    }

    private func write() {
        do {
            try store.save(configuration)
        } catch {
            Log.app.error("Failed to save configuration: \(String(describing: error), privacy: .public)")
        }
    }
}
