import AppKit
import NexusCore

// Single instance (§1 of DESIGN_MVP): if another Nexus is already running, hand over to it.
let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.congbui.nexus"
let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if let existing = others.first {
    Log.app.info("Another Nexus instance is running; activating it and exiting")
    existing.activate()
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
