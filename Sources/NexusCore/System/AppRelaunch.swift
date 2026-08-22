import AppKit
import Foundation

/// Restarting Nexus in place.
///
/// macOS hands a process its Accessibility trust at launch and does not always refresh it for an
/// already-running process — and with an unstable (ad-hoc) signature the TCC entry can stop
/// matching the running binary entirely, so `AXIsProcessTrusted()` stays `false` no matter how
/// many times the user flips the switch. A restart is the only reliable remedy, so the
/// explain-and-grant screen offers one.
@MainActor
public enum AppRelaunch {
    /// Set on the replacement process so its single-instance guard waits for the outgoing one
    /// instead of deferring to it.
    public static let environmentKey = "NEXUS_RELAUNCHING"

    public static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.environment = [environmentKey: "1"]
        let bundleURL = Bundle.main.bundleURL

        Log.app.notice("Relaunching to pick up a permission change")
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
            if let error {
                Log.app.error("Relaunch failed: \(String(describing: error), privacy: .public)")
            }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    /// Called by the replacement process. Waits for the outgoing instance to exit rather than
    /// treating it as the incumbent and bowing out.
    public static func waitForOutgoingInstance(
        bundleIdentifier: String,
        timeout: TimeInterval = 5
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let others = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if others.isEmpty { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        Log.app.error("Outgoing Nexus instance did not exit within \(timeout, privacy: .public) s")
    }
}
