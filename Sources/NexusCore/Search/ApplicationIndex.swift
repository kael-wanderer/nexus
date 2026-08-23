import AppKit
import Foundation

/// Thread-safe snapshot holder, so the main-actor index can publish to `Sendable` providers.
public final class ApplicationIndexSnapshot: Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var applications: [NexusApplication] = []

    public init() {}

    public func read() -> [NexusApplication] {
        lock.lock()
        defer { lock.unlock() }
        return applications
    }

    public func write(_ applications: [NexusApplication]) {
        lock.lock()
        self.applications = applications
        lock.unlock()
    }
}

/// The application catalogue behind search. Spotlight finds application bundles anywhere on disk
/// (D8); when Spotlight is disabled or empty, a scan of the standard directories takes over.
/// Built lazily on the first search — nothing is indexed at launch (§10 cold start).
@MainActor
public final class ApplicationIndex {
    public let snapshot = ApplicationIndexSnapshot()

    private let events: EventBus
    private var buildTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var hasBuilt = false
    private var usedFallback = false

    public init(events: EventBus) {
        self.events = events
    }

    public var isUsingDirectoryFallback: Bool { usedFallback }
    /// Called on the main actor when a build finishes. The start menu opens before the first
    /// build can complete, so it needs telling rather than polling.
    public var onIndexed: (() -> Void)?

    public func start() {
        let stream = events.events()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                // A newly installed application shows up when it is first launched; Nexus does
                // not keep a Spotlight query live for the lifetime of the process.
                if case .applicationLaunched = event, self.hasBuilt { self.rebuild() }
            }
        }
    }

    public func stop() {
        buildTask?.cancel()
        eventTask?.cancel()
    }

    /// Called when the search palette opens. Cheap after the first build.
    public func ensureBuilt() {
        guard !hasBuilt else { return }
        hasBuilt = true
        rebuild()
    }

    private func rebuild() {
        buildTask?.cancel()
        buildTask = Task { [weak self] in
            guard let self else { return }
            let spotlight = await MetadataQueryRunner.shared.run(
                .applicationBundles,
                scope: .localComputer,
                limit: 4_000
            )
            guard !Task.isCancelled else { return }

            var urls = spotlight.map(\.url)
            if urls.isEmpty {
                self.usedFallback = true
                urls = Self.scanStandardDirectories()
                Log.search.notice("Spotlight returned no applications; scanned \(urls.count, privacy: .public) from standard directories")
            } else {
                self.usedFallback = false
            }
            self.snapshot.write(Self.applications(from: urls))
            Log.search.notice("Application index: \(self.snapshot.read().count, privacy: .public) applications")
            self.onIndexed?()
        }
    }

    static let standardDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/Applications/Utilities"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
    ]

    static func scanStandardDirectories() -> [URL] {
        var found: [URL] = []
        for directory in standardDirectories {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            found.append(contentsOf: contents.filter { $0.pathExtension == "app" })
        }
        return found
    }

    /// Spotlight returns every application bundle on the disk, most of which nobody launches:
    /// agents that declare `LSUIElement` or `LSBackgroundOnly`, helpers nested inside another
    /// bundle, input methods, and the `CoreServices` scaffolding behind "About This Mac" (D68).
    static func isLaunchable(_ url: URL, _ bundle: Bundle) -> Bool {
        if bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true { return false }
        if bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool == true { return false }
        // "1"/"YES" appear as strings in older bundles.
        if let raw = bundle.object(forInfoDictionaryKey: "LSUIElement") as? String, raw != "0" {
            return false
        }
        let path = url.path
        // A helper inside another application, e.g. Foo.app/Contents/…/Foo Helper.app.
        if path.contains(".app/Contents/") { return false }
        let excludedPrefixes = [
            "/System/Library/CoreServices",
            "/System/Library/PrivateFrameworks",
            "/System/Library/Frameworks",
            "/System/Library/Input Methods",
            "/Library/Input Methods",
            "/System/Library/Assistant",
            "/System/iOSSupport",
        ]
        return !excludedPrefixes.contains { path.hasPrefix($0) }
    }

    static func applications(from urls: [URL]) -> [NexusApplication] {
        var seen = Set<String>()
        var applications: [NexusApplication] = []
        for url in urls {
            guard let bundle = Bundle(url: url),
                  let identifier = bundle.bundleIdentifier,
                  Self.isLaunchable(url, bundle),
                  seen.insert(identifier).inserted
            else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            applications.append(
                NexusApplication(
                    identity: ApplicationIdentity(bundleIdentifier: identifier),
                    name: name,
                    bundleURL: url
                )
            )
        }
        return applications
    }
}
