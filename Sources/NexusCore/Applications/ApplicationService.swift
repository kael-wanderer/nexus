import AppKit
import Foundation

public protocol ApplicationServing: Sendable {
    /// Metadata for an application whether or not it is running. `nil` when the bundle is gone.
    func application(for identity: ApplicationIdentity) async -> NexusApplication?
    func runningApplications() async -> [NexusApplication]
    func launch(_ identity: ApplicationIdentity) async throws
    func activate(_ identity: ApplicationIdentity) async throws
    func quit(_ identity: ApplicationIdentity, force: Bool) async throws
    func revealInFinder(_ identity: ApplicationIdentity) async
}

/// `NSWorkspace` / `NSRunningApplication` over an actor. Every AppKit object stays inside the
/// call that produced it; only `Sendable` value types leave.
public actor ApplicationService: ApplicationServing {
    private var metadataCache: [String: NexusApplication] = [:]
    private var windowCounts: [pid_t: Int] = [:]
    private var activeBundleIdentifier: String?

    public init() {}

    // MARK: - Reads

    public func application(for identity: ApplicationIdentity) -> NexusApplication? {
        let bundleIdentifier = identity.bundleIdentifier
        if let running = liveApplications().first(where: { $0.identity == identity }) {
            metadataCache[bundleIdentifier] = running
            return running
        }
        if var cached = metadataCache[bundleIdentifier] {
            cached.isRunning = false
            cached.isActive = false
            cached.windowCount = 0
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            Log.applications.debug("No bundle on disk for \(bundleIdentifier, privacy: .public)")
            return nil
        }
        let application = NexusApplication(
            identity: ApplicationIdentity(bundleIdentifier: bundleIdentifier),
            name: Self.displayName(for: url),
            bundleURL: url
        )
        metadataCache[bundleIdentifier] = application
        return application
    }

    public func runningApplications() -> [NexusApplication] {
        let applications = liveApplications()
        for application in applications { metadataCache[application.identity.bundleIdentifier] = application }
        return applications
    }

    /// Window counts come from `CGWindowListCopyWindowInfo` (D5) and are pushed in by
    /// `ApplicationMonitor`; they need no permission and cost one call for every app at once.
    public func updateWindowCounts(_ counts: [pid_t: Int]) {
        windowCounts = counts
    }

    public func updateActiveApplication(_ bundleIdentifier: String?) {
        activeBundleIdentifier = bundleIdentifier
    }

    private func liveApplications() -> [NexusApplication] {
        NSWorkspace.shared.runningApplications.compactMap { running in
            guard running.activationPolicy == .regular,
                  let bundleIdentifier = running.bundleIdentifier,
                  let url = running.bundleURL
            else { return nil }
            return NexusApplication(
                identity: ApplicationIdentity(
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: running.processIdentifier
                ),
                name: running.localizedName ?? Self.displayName(for: url),
                bundleURL: url,
                isRunning: true,
                isActive: bundleIdentifier == activeBundleIdentifier,
                windowCount: windowCounts[running.processIdentifier] ?? 0
            )
        }
    }

    private static func displayName(for url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Actions

    public func launch(_ identity: ApplicationIdentity) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identity.bundleIdentifier) else {
            Log.applications.error("Launch failed: LaunchServices knows no \(identity.bundleIdentifier, privacy: .public)")
            throw NexusError.notFound
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            Log.applications.notice("Launched \(identity.bundleIdentifier, privacy: .public)")
        } catch {
            Log.applications.error(
                "Launch failed for \(identity.bundleIdentifier, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            throw NexusError.notFound
        }
    }

    /// Activation goes through LaunchServices, not `NSRunningApplication.activate()`. The latter
    /// only brings the process forward: an application whose windows are all closed or hidden —
    /// a menu-bar app, say — comes to the front showing nothing, which reads as a dead click.
    /// Opening it again sends the reopen event the Dock sends, so the application shows a window.
    public func activate(_ identity: ApplicationIdentity) async throws {
        guard let url = await Self.withRunningApplication(identity, { $0.bundleURL }) ?? nil else {
            Log.applications.error("Activate failed: \(identity.bundleIdentifier, privacy: .public) is not running")
            throw NexusError.targetDisappeared
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            Log.applications.error(
                "Activate failed for \(identity.bundleIdentifier, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            throw NexusError.targetDisappeared
        }
        Log.applications.notice("Activated \(identity.bundleIdentifier, privacy: .public)")
    }

    public func quit(_ identity: ApplicationIdentity, force: Bool) async throws {
        let quit = await Self.withRunningApplication(identity) { running in
            force ? running.forceTerminate() : running.terminate()
        }
        guard quit == true else {
            Log.applications.error("Quit failed: \(identity.bundleIdentifier, privacy: .public) is not running")
            throw NexusError.targetDisappeared
        }
        Log.applications.notice(
            "Requested \(force ? "force quit" : "quit", privacy: .public) of \(identity.bundleIdentifier, privacy: .public)"
        )
    }

    public func revealInFinder(_ identity: ApplicationIdentity) async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identity.bundleIdentifier) else { return }
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// `NSRunningApplication` is not `Sendable`; every use of one is confined to the main actor.
    @MainActor
    private static func withRunningApplication<Result>(
        _ identity: ApplicationIdentity,
        _ body: (NSRunningApplication) -> Result
    ) -> Result? {
        let candidates = NSRunningApplication.runningApplications(
            withBundleIdentifier: identity.bundleIdentifier
        )
        guard let running = candidates.first else { return nil }
        return body(running)
    }
}
