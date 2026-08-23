import Foundation
import Testing
@testable import NexusCore

/// No test may write to the real `com.apple.dock` domain, so the controller is exercised against
/// this instead. It also records the call order, which is what most of the lifecycle rules are.
@MainActor
final class FakeDockControl: DockControlling {
    enum Call: Equatable {
        case snapshot
        case apply(SidebarPosition)
        case restore(DockSnapshot)
    }

    /// What the "user's own" Dock settings look like.
    var current = DockSnapshot(autohide: false, autohideDelay: nil, orientation: "bottom")
    private(set) var calls: [Call] = []
    var hidden = false

    func snapshot() -> DockSnapshot {
        calls.append(.snapshot)
        return current
    }

    func apply(sidebarPosition: SidebarPosition) {
        calls.append(.apply(sidebarPosition))
        hidden = true
    }

    func restore(_ snapshot: DockSnapshot) {
        calls.append(.restore(snapshot))
        hidden = false
    }

    var isDockHidden: Bool { hidden }

    var applyCount: Int { calls.filter { if case .apply = $0 { true } else { false } }.count }
    var snapshotCount: Int { calls.filter { $0 == .snapshot }.count }
    var restored: [DockSnapshot] { calls.compactMap { if case .restore(let s) = $0 { s } else { nil } } }
}

@MainActor
private func makeController(
    _ mutate: (inout NexusConfiguration) -> Void = { _ in }
) -> (DockReplacementController, ConfigurationController, FakeDockControl) {
    let configuration = ConfigurationController(
        store: InMemoryConfigurationStore(),
        events: EventBus(),
        saveDelay: .zero
    )
    configuration.update(mutate)
    let dock = FakeDockControl()
    return (DockReplacementController(configuration: configuration, dock: dock), configuration, dock)
}

@MainActor
@Suite("Dock replacement lifecycle")
struct DockReplacementTests {
    @Test("Enabling captures the user's settings, then hides the Dock")
    func enabling() {
        let (controller, configuration, dock) = makeController()
        dock.current = DockSnapshot(autohide: false, orientation: "bottom")

        controller.setEnabled(true)

        #expect(dock.calls == [.snapshot, .apply(.left)])
        #expect(configuration.configuration.dock.replacementEnabled)
        #expect(configuration.configuration.dock.applied)
        #expect(configuration.configuration.dock.snapshot?.orientation == "bottom")
    }

    @Test("Enabling twice never overwrites the captured settings")
    func enablingTwice() {
        let (controller, configuration, dock) = makeController()
        dock.current = DockSnapshot(autohide: false, orientation: "bottom")
        controller.setEnabled(true)

        // What the Dock looks like *after* Nexus changed it. Capturing this would mean restoring
        // Nexus's own settings later — the user's Dock would never come back.
        dock.current = DockSnapshot(autohide: true, autohideDelay: 1000, orientation: "right")
        controller.setEnabled(true)

        #expect(dock.snapshotCount == 1)
        #expect(configuration.configuration.dock.snapshot?.orientation == "bottom")
        #expect(configuration.configuration.dock.snapshot?.autohide == false)
    }

    @Test("Disabling restores exactly what was captured")
    func disabling() {
        let (controller, configuration, dock) = makeController()
        let original = DockSnapshot(autohide: false, autohideDelay: 0.5, orientation: "bottom")
        dock.current = original
        controller.setEnabled(true)

        controller.setEnabled(false)

        #expect(dock.restored.count == 1)
        #expect(dock.restored[0].orientation == original.orientation)
        #expect(dock.restored[0].autohideDelay == original.autohideDelay)
        #expect(!configuration.configuration.dock.replacementEnabled)
        #expect(!configuration.configuration.dock.applied)
    }

    @Test("A key the user never set stays unset on restore")
    func unsetKeysStayUnset() {
        let (controller, _, dock) = makeController()
        dock.current = DockSnapshot(autohide: nil, autohideDelay: nil, autohideTimeModifier: nil, orientation: nil)
        controller.setEnabled(true)

        controller.setEnabled(false)

        #expect(dock.restored[0].autohide == nil)
        #expect(dock.restored[0].autohideDelay == nil)
        #expect(dock.restored[0].autohideTimeModifier == nil)
        #expect(dock.restored[0].orientation == nil)
    }

    @Test("Quitting restores the Dock but keeps the mode switched on")
    func quitting() {
        let (controller, configuration, dock) = makeController()
        controller.setEnabled(true)

        controller.stop()

        #expect(dock.restored.count == 1)
        #expect(!configuration.configuration.dock.applied)
        #expect(configuration.configuration.dock.replacementEnabled)
    }

    @Test("Launching with the mode on re-applies it")
    func launchingEnabled() {
        let (controller, configuration, dock) = makeController {
            $0.dock.replacementEnabled = true
            $0.dock.applied = false
        }

        controller.start()

        #expect(dock.applyCount == 1)
        #expect(configuration.configuration.dock.applied)
    }

    @Test("Launching after a crash that left the Dock hidden restores it")
    func launchingAfterCrash() {
        let captured = DockSnapshot(autohide: false, orientation: "bottom")
        let (controller, configuration, dock) = makeController {
            // What a SIGKILL leaves behind: applied, but nobody asked for the mode any more.
            $0.dock.replacementEnabled = false
            $0.dock.applied = true
            $0.dock.snapshot = captured
        }

        controller.start()

        #expect(dock.restored.count == 1)
        #expect(dock.restored[0].orientation == "bottom")
        #expect(!configuration.configuration.dock.applied)
    }

    @Test("Launching with the mode off and nothing applied leaves the Dock alone")
    func launchingDisabled() {
        let (controller, _, dock) = makeController()

        controller.start()

        #expect(dock.calls.isEmpty)
    }

    @Test("Moving the sidebar moves the Dock out of its way, without re-capturing")
    func positionChange() {
        let (controller, configuration, dock) = makeController()
        controller.setEnabled(true)

        configuration.update { $0.appearance.position = .bottom }
        controller.sidebarPositionChanged()

        #expect(dock.calls.last == .apply(.bottom))
        #expect(dock.snapshotCount == 1)
    }

    @Test("Restore Now works even when the flags say the mode is off")
    func restoreNow() {
        let captured = DockSnapshot(autohide: false, orientation: "bottom")
        let (controller, configuration, dock) = makeController {
            $0.dock.replacementEnabled = false
            $0.dock.applied = true
            $0.dock.snapshot = captured
        }

        controller.restoreNow()

        #expect(dock.restored.count == 1)
        #expect(!configuration.configuration.dock.applied)
    }

    @Test("The Dock is parked away from the sidebar's edge")
    func dockOrientation() {
        #expect(DockControlService.dockOrientation(besides: .left) == "right")
        #expect(DockControlService.dockOrientation(besides: .right) == "left")
        // The Dock has no top edge, so a horizontal bar sends it sideways instead.
        #expect(DockControlService.dockOrientation(besides: .top) == "left")
        #expect(DockControlService.dockOrientation(besides: .bottom) == "left")
    }
}
