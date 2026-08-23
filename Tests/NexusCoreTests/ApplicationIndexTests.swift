import Foundation
import Testing

@testable import NexusCore

@MainActor
@Suite("Application index")
struct ApplicationIndexTests {
    /// Builds a throwaway `.app` whose Info.plist holds exactly the given keys.
    private func makeBundle(_ name: String, _ keys: [String: Any]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let bundle = root.appendingPathComponent("\(name).app")
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist = keys
        plist["CFBundlePackageType"] = "APPL"
        try (plist as NSDictionary).write(
            to: contents.appendingPathComponent("Info.plist")
        )
        return bundle
    }

    @Test("A bundle shipping an empty name falls back to its file name, not a blank caption")
    func emptyName() throws {
        let url = try makeBundle("Wide Angle", [
            "CFBundleIdentifier": "com.example.wide",
            "CFBundleName": "",
            "CFBundleDisplayName": "   ",
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let applications = ApplicationIndex.applications(from: [url])
        #expect(applications.map(\.name) == ["Wide Angle"])
    }

    @Test("A display name wins over the bundle name")
    func displayNameWins() throws {
        let url = try makeBundle("Legacy", [
            "CFBundleIdentifier": "com.example.legacy",
            "CFBundleName": "Legacy",
            "CFBundleDisplayName": "Shiny",
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(ApplicationIndex.applications(from: [url]).map(\.name) == ["Shiny"])
    }

    @Test("Agents and in-bundle helpers are left out of the index")
    func filtersUnlaunchable() throws {
        let agent = try makeBundle("Agent", [
            "CFBundleIdentifier": "com.example.agent",
            "CFBundleName": "Agent",
            "LSUIElement": true,
        ])
        defer { try? FileManager.default.removeItem(at: agent.deletingLastPathComponent()) }

        #expect(ApplicationIndex.applications(from: [agent]).isEmpty)
    }
}
