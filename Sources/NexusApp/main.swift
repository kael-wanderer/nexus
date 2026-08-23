import AppKit
import NexusCore

// Single instance (§1 of design/mvp.md): if another Nexus is already running, hand over to it.
// The one exception is a deliberate relaunch, where the outgoing instance is on its way out and
// this process is its replacement.
let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.congbui.nexus"

if ProcessInfo.processInfo.environment[AppRelaunch.environmentKey] != nil {
    AppRelaunch.waitForOutgoingInstance(bundleIdentifier: bundleIdentifier)
} else {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if let existing = others.first {
        Log.app.notice("Another Nexus instance is running; activating it and exiting")
        existing.activate()
        exit(0)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
