import Foundation
import NexusCore

/// Injected fake — no test touches the real `NSWorkspace` or launches anything (§67).
actor FakeApplicationService: ApplicationServing {
    private var catalogue: [String: NexusApplication] = [:]
    private(set) var launched: [String] = []
    private(set) var activated: [String] = []
    private(set) var quit: [(String, Bool)] = []
    private(set) var revealed: [String] = []

    init(_ applications: [NexusApplication] = []) {
        for application in applications { catalogue[application.identity.bundleIdentifier] = application }
    }

    func define(_ application: NexusApplication) {
        catalogue[application.identity.bundleIdentifier] = application
    }

    func setRunning(_ bundleIdentifier: String, _ running: Bool, windowCount: Int = 0) {
        guard var application = catalogue[bundleIdentifier] else { return }
        application.isRunning = running
        application.windowCount = windowCount
        catalogue[bundleIdentifier] = application
    }

    func application(for identity: ApplicationIdentity) async -> NexusApplication? {
        catalogue[identity.bundleIdentifier]
    }

    func runningApplications() async -> [NexusApplication] {
        catalogue.values.filter(\.isRunning).sorted { $0.name < $1.name }
    }

    func launch(_ identity: ApplicationIdentity) async throws {
        guard catalogue[identity.bundleIdentifier] != nil else { throw NexusError.notFound }
        launched.append(identity.bundleIdentifier)
    }

    func activate(_ identity: ApplicationIdentity) async throws {
        activated.append(identity.bundleIdentifier)
    }

    func quit(_ identity: ApplicationIdentity, force: Bool) async throws {
        quit.append((identity.bundleIdentifier, force))
    }

    func revealInFinder(_ identity: ApplicationIdentity) async {
        revealed.append(identity.bundleIdentifier)
    }
}

/// Where in a row a drag is, as `dragMoved(over:at:)` wants it: normalised, and the same on both
/// axes so one point works whichever way the bar runs.
extension CGPoint {
    static let leadingEdge = CGPoint(x: 0.05, y: 0.05)
    static let middle = CGPoint(x: 0.5, y: 0.5)
    static let trailingEdge = CGPoint(x: 0.95, y: 0.95)
}

func makeApplication(
    _ bundleIdentifier: String,
    name: String,
    running: Bool = false,
    windowCount: Int = 0
) -> NexusApplication {
    NexusApplication(
        identity: ApplicationIdentity(bundleIdentifier: bundleIdentifier),
        name: name,
        bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"),
        isRunning: running,
        windowCount: windowCount
    )
}
