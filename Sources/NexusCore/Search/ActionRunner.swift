import AppKit
import Foundation

/// The one place that performs a `NexusActionDescriptor`'s side effect (D6). No shell, no
/// AppleScript, no `osascript` (D15).
@MainActor
public final class ActionRunner {
    private let applications: any ApplicationServing
    private let windows: any WindowServing

    public init(applications: any ApplicationServing, windows: any WindowServing) {
        self.applications = applications
        self.windows = windows
    }

    /// `true` when the action moves focus somewhere else, so the caller must not restore the
    /// previously frontmost application.
    @discardableResult
    public func run(_ action: NexusActionDescriptor) -> Bool {
        switch action {
        case .launchApplication(let bundleIdentifier):
            let identity = ApplicationIdentity(bundleIdentifier: bundleIdentifier)
            Task { [applications] in
                if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                    try? await applications.launch(identity)
                } else {
                    try? await applications.activate(identity)
                }
            }
            return true

        case .activateWindow(let identity):
            Task { [windows] in try? await windows.activate(identity) }
            return true

        case .openFile(let url):
            NSWorkspace.shared.open(url)
            return true

        case .openURL(let url):
            NSWorkspace.shared.open(url)
            return true

        case .quitApplication(let bundleIdentifier):
            Task { [applications] in
                try? await applications.quit(
                    ApplicationIdentity(bundleIdentifier: bundleIdentifier),
                    force: false
                )
            }
            return false

        case .runBuiltInAction(let builtIn):
            return runBuiltIn(builtIn)
        }
    }

    private func runBuiltIn(_ action: BuiltInAction) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch action {
        case .openTerminal:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
            else { return false }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return true
        case .openDownloads:
            NSWorkspace.shared.open(home.appendingPathComponent("Downloads"))
            return true
        case .openDocuments:
            NSWorkspace.shared.open(home.appendingPathComponent("Documents"))
            return true
        case .openHome:
            NSWorkspace.shared.open(home)
            return true
        case .openSystemSettings:
            guard let url = URL(string: "x-apple.systempreferences:") else { return false }
            NSWorkspace.shared.open(url)
            return true
        case .lockScreen:
            return Self.lockScreen()
        }
    }

    /// `SACLockScreenImmediate` lives in a private framework, so it is resolved at runtime: if it
    /// ever disappears the action fails quietly instead of failing to build or crashing.
    private static func lockScreen() -> Bool {
        typealias LockFunction = @convention(c) () -> Int32
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/login.framework/Versions/A/login",
            RTLD_LAZY
        ) else {
            Log.system.error("Lock Screen unavailable: login framework did not load")
            return false
        }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            Log.system.error("Lock Screen unavailable: SACLockScreenImmediate not found")
            return false
        }
        _ = unsafeBitCast(symbol, to: LockFunction.self)()
        return true
    }
}
