import Foundation

/// Owns when the Dock is hidden and when it comes back (D52).
///
/// The rule the whole design hangs on: **Dock-less exists only while Nexus runs.** Quitting
/// restores, launching re-applies. That is also the uninstall story — macOS gives an application
/// no uninstall hook, so the only reliable answer is that the Dock is normal whenever Nexus is
/// not running.
@MainActor
public final class DockReplacementController {
    private let configuration: ConfigurationController
    private let dock: any DockControlling

    public init(configuration: ConfigurationController, dock: any DockControlling) {
        self.configuration = configuration
        self.dock = dock
    }

    public var isEnabled: Bool { configuration.configuration.dock.replacementEnabled }
    public var isApplied: Bool { configuration.configuration.dock.applied }
    /// Read from the Dock itself, not from our own flag, so the UI stays honest when the user
    /// changes the Dock behind Nexus's back.
    public var isDockHidden: Bool { dock.isDockHidden }

    /// At launch: re-apply what the user asked for, or clean up after a run that never got to
    /// restore — a crash, or `SIGKILL`, where no termination handler runs.
    public func start() {
        let state = configuration.configuration.dock
        if state.replacementEnabled {
            apply()
        } else if state.applied {
            Log.system.notice("Dock was left hidden by a previous run; restoring")
            restore()
        }
    }

    /// At quit. Leaves `replacementEnabled` alone: the mode is still what the user wants, it is
    /// simply not in force while Nexus is not running.
    public func stop() {
        guard configuration.configuration.dock.applied else { return }
        restore()
        configuration.flush()
    }

    public func setEnabled(_ enabled: Bool) {
        if enabled {
            apply()
        } else {
            restore()
            configuration.update { $0.dock.replacementEnabled = false }
        }
    }

    /// The sidebar moved to another edge, so the Dock has to move out of its way again.
    public func sidebarPositionChanged() {
        guard configuration.configuration.dock.applied else { return }
        dock.apply(sidebarPosition: configuration.configuration.appearance.position)
    }

    /// Always available, whatever the flags say — the button a stuck user reaches for.
    public func restoreNow() {
        restore()
        configuration.update { $0.dock.replacementEnabled = false }
        configuration.flush()
    }

    // MARK: - Private

    private func apply() {
        let position = configuration.configuration.appearance.position
        // Capture only when the Dock is in the user's own state. Applying twice must not
        // overwrite the snapshot with Nexus's own values.
        let captured = configuration.configuration.dock.applied
            ? configuration.configuration.dock.snapshot
            : dock.snapshot()
        dock.apply(sidebarPosition: position)
        configuration.update {
            $0.dock.snapshot = captured
            $0.dock.applied = true
            $0.dock.replacementEnabled = true
        }
    }

    private func restore() {
        if let snapshot = configuration.configuration.dock.snapshot {
            dock.restore(snapshot)
        }
        configuration.update { $0.dock.applied = false }
    }
}
