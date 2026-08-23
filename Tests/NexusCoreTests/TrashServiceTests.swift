import Foundation
import Testing

@testable import NexusCore

/// The Trash count comes from `stat` link counts, because `readdir` on `~/.Trash` needs Full Disk
/// Access (D58). These run against scratch directories — never the real Trash.
@Suite("Trash contents")
struct TrashServiceTests {
    private func scratch() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nexus-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ directory: URL, _ name: String) throws {
        try Data().write(to: directory.appendingPathComponent(name))
    }

    @Test("An empty directory counts as empty")
    func empty() throws {
        let url = try scratch()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(TrashService.entryCount(in: url.path) == 0)
    }

    @Test("Files are counted, one link each")
    func counts() throws {
        let url = try scratch()
        defer { try? FileManager.default.removeItem(at: url) }
        try touch(url, "one.txt")
        #expect(TrashService.entryCount(in: url.path) == 1)
        try touch(url, "two.txt")
        #expect(TrashService.entryCount(in: url.path) == 2)
    }

    /// The case that decides whether the icon is usable: Finder recreates `.DS_Store` as soon as
    /// the Trash window is opened, so counting it would leave the full icon showing forever.
    @Test("Finder's own housekeeping files do not make the Trash look full")
    func housekeepingIgnored() throws {
        let url = try scratch()
        defer { try? FileManager.default.removeItem(at: url) }
        try touch(url, ".DS_Store")
        #expect(TrashService.entryCount(in: url.path) == 0)

        try touch(url, ".localized")
        #expect(TrashService.entryCount(in: url.path) == 0)

        try touch(url, "receipt.pdf")
        #expect(TrashService.entryCount(in: url.path) == 1)
    }

    @Test("Directories count too, and a path that does not exist reads as empty")
    func directoriesAndMissingPaths() throws {
        let url = try scratch()
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("Some.app"),
            withIntermediateDirectories: false
        )
        #expect(TrashService.entryCount(in: url.path) == 1)
        #expect(TrashService.entryCount(in: url.path + "/nowhere") == 0)
    }
}
