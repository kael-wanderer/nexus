import AppKit
import Foundation

/// Dock Replacement Mode (D51/D52). The only code in Nexus that reads or writes the
/// `com.apple.dock` domain.
///
/// A protocol so tests get a fake: no test may write to the real Dock domain, the same rule that
/// already protects `com.congbui.nexus`.
@MainActor
public protocol DockControlling: Sendable {
    /// The user's current Dock settings, for stashing before Nexus changes them.
    func snapshot() -> DockSnapshot
    /// Hides the Dock and parks it away from the sidebar's edge.
    func apply(sidebarPosition: SidebarPosition)
    /// Puts back exactly what `snapshot()` returned — deleting the keys that had no value.
    func restore(_ snapshot: DockSnapshot)
    /// Live state, so the UI can tell the truth even when the Dock was changed behind Nexus's back.
    var isDockHidden: Bool { get }
}

/// `defaults` keys plus a Dock restart — the only supported way to get the Dock out of the way.
///
/// Rejected `NSApplicationPresentationHideDock`: presentation options apply only while the owning
/// application is active, and Nexus is an `LSUIElement` that never activates, so the Dock would
/// come back the moment focus moved (D51). Nothing here touches `Dock.app`, system files or SIP.
@MainActor
public struct DockControlService: DockControlling {
    private static let domain = "com.apple.dock"

    private enum Key {
        static let autohide = "autohide"
        static let autohideDelay = "autohide-delay"
        static let autohideTimeModifier = "autohide-time-modifier"
        static let orientation = "orientation"
    }

    /// ~17 minutes of uninterrupted hovering before the Dock peeks out. Auto-hide alone is not
    /// enough — the Dock still slides in on every brush of the screen edge.
    public static let hiddenDelay: Double = 1000

    /// Anything at or above this counts as "Nexus is hiding it" for the status indicator; a user
    /// who picked their own long delay is indistinguishable, and that is fine.
    private static let hiddenDelayThreshold: Double = 10

    public init() {}

    // MARK: - Reading

    public func snapshot() -> DockSnapshot {
        DockSnapshot(
            autohide: bool(Key.autohide),
            autohideDelay: double(Key.autohideDelay),
            autohideTimeModifier: double(Key.autohideTimeModifier),
            orientation: string(Key.orientation)
        )
    }

    public var isDockHidden: Bool {
        bool(Key.autohide) == true && (double(Key.autohideDelay) ?? 0) >= Self.hiddenDelayThreshold
    }

    // MARK: - Writing

    public func apply(sidebarPosition: SidebarPosition) {
        set(Key.autohide, true as CFBoolean)
        set(Key.autohideDelay, Self.hiddenDelay as CFNumber)
        set(Key.autohideTimeModifier, 0 as CFNumber)
        set(Key.orientation, Self.dockOrientation(besides: sidebarPosition) as CFString)
        synchronizeAndRestart()
        Log.system.notice(
            "Dock replacement applied (sidebar \(sidebarPosition.rawValue, privacy: .public), dock \(Self.dockOrientation(besides: sidebarPosition), privacy: .public))"
        )
    }

    public func restore(_ snapshot: DockSnapshot) {
        set(Key.autohide, snapshot.autohide.map { $0 as CFBoolean })
        set(Key.autohideDelay, snapshot.autohideDelay.map { $0 as CFNumber })
        set(Key.autohideTimeModifier, snapshot.autohideTimeModifier.map { $0 as CFNumber })
        set(Key.orientation, snapshot.orientation.map { $0 as CFString })
        synchronizeAndRestart()
        Log.system.notice("Dock restored to the settings captured at \(snapshot.capturedAt, privacy: .public)")
    }

    /// The Dock has no top edge, so a horizontal sidebar sends it to the left rather than to the
    /// literal opposite. Sharing an edge would put the Dock's hot zone under Nexus's own edge
    /// trigger, where every stray mouse flick arms a 1000-second timer.
    static func dockOrientation(besides sidebarPosition: SidebarPosition) -> String {
        switch sidebarPosition {
        case .left: "right"
        case .right, .top, .bottom: "left"
        }
    }

    // MARK: - CFPreferences

    private func bool(_ key: String) -> Bool? {
        CFPreferencesCopyAppValue(key as CFString, Self.domain as CFString) as? Bool
    }

    private func double(_ key: String) -> Double? {
        CFPreferencesCopyAppValue(key as CFString, Self.domain as CFString) as? Double
    }

    private func string(_ key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, Self.domain as CFString) as? String
    }

    /// `nil` deletes the key. A key the user never set must come back unset, not set to a
    /// plausible-looking default.
    private func set(_ key: String, _ value: CFTypeRef?) {
        CFPreferencesSetAppValue(key as CFString, value, Self.domain as CFString)
    }

    /// The Dock reads its preferences at start-up, so the restart is not optional. Terminating it
    /// is `killall Dock` without a shell — `launchd` brings it straight back.
    private func synchronizeAndRestart() {
        CFPreferencesAppSynchronize(Self.domain as CFString)
        _ = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?
            .terminate()
    }
}
