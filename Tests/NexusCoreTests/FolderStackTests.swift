import Foundation
import NexusCore
import Testing

/// A directory that cleans itself up, so a listing test needs no fixture checked into the repo.
private struct TemporaryDirectory: ~Copyable {
    let url: URL

    init(_ build: (URL) throws -> Void) throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nexus-stack-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try build(url)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

private func write(_ name: String, in directory: URL) throws {
    try Data().write(to: directory.appendingPathComponent(name))
}

@Suite("Folder stacks")
struct FolderStackTests {
    @Test("A listing puts folders first, then files, each in name order")
    func sortsFoldersFirst() throws {
        let directory = try TemporaryDirectory { url in
            try write("beta.txt", in: url)
            try write("alpha.txt", in: url)
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent("Zebra"), withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent("Apples"), withIntermediateDirectories: true
            )
        }
        let items = FolderStackService.list(directory.url).items
        #expect(items.map(\.name) == ["Apples", "Zebra", "alpha.txt", "beta.txt"])
        #expect(items.prefix(2).map(\.isDirectory) == [true, true])
    }

    @Test("Hidden files are not stack items")
    func skipsHiddenFiles() throws {
        let directory = try TemporaryDirectory { url in
            try write(".DS_Store", in: url)
            try write("visible.txt", in: url)
        }
        #expect(FolderStackService.list(directory.url).items.map(\.name) == ["visible.txt"])
    }

    @Test("A long listing is capped, and the cap is the only thing it changes")
    func capsTheListing() throws {
        let directory = try TemporaryDirectory { url in
            for index in 0..<12 { try write(String(format: "file-%02d.txt", index), in: url) }
        }
        let items = FolderStackService.list(directory.url, limit: 5).items
        #expect(items.count == 5)
        #expect(items.first?.name == "file-00.txt")
    }

    @Test("A folder that is not there is missing, not empty")
    func missingFolder() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nexus-not-here-\(UUID().uuidString)")
        #expect(FolderStackService.list(url) == .missing)
    }

    @Test("A file pinned as if it were a folder is missing rather than listed")
    func fileIsNotAFolder() throws {
        let directory = try TemporaryDirectory { url in try write("solo.txt", in: url) }
        let file = directory.url.appendingPathComponent("solo.txt")
        #expect(FolderStackService.list(file) == .missing)
    }

    @Test("A directory that cannot be read is refused, which is not the same as empty")
    func refusedFolder() throws {
        let directory = try TemporaryDirectory { url in
            try write("secret.txt", in: url)
            // No search permission: reading the entries fails the way a TCC refusal does.
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        }
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: directory.url.path
            )
        }
        #expect(FolderStackService.list(directory.url) == .refused)
    }

    @Test("A package is one item, not a directory to walk into")
    func packageIsAnItem() throws {
        let directory = try TemporaryDirectory { url in
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent("Thing.app"), withIntermediateDirectories: true
            )
        }
        let items = FolderStackService.list(directory.url).items
        #expect(items.count == 1)
        #expect(items[0].isDirectory == false)
    }
}

@Suite("Folder entries in the dock")
struct FolderEntryTests {
    @Test("A folder entry round-trips as a path, and reads back as itself")
    func roundTrips() throws {
        let entries: [DockEntry] = [.application("com.apple.Safari"), .folder("/Users/x/Downloads")]
        let data = try JSONEncoder().encode(entries)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"folder\":\"\\/Users\\/x\\/Downloads\""))
        let decoded = try JSONDecoder().decode([DockEntry].self, from: data)
        #expect(decoded == entries)
    }

    @Test("An entry that is none of the three kinds still throws")
    func unknownKindThrows() {
        let data = Data(#"[{"widget": "nope"}]"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode([DockEntry].self, from: data)
        }
    }

    @Test("A folder's id is distinct from a bundle identifier and from a group's")
    func identity() {
        #expect(DockEntry.folder("/tmp").id == "folder:/tmp")
        #expect(DockEntry.folder("/tmp").applications.isEmpty)
        #expect(DockEntry.folder("/tmp").folderPath == "/tmp")
        #expect(DockEntry.application("com.apple.Safari").folderPath == nil)
    }

    @Test("Repair keeps folders, drops empty paths and de-duplicates")
    func repairs() {
        let entries: [DockEntry] = [
            .folder("/Users/x/Downloads"),
            .application("com.apple.Safari"),
            .folder("/Users/x/Downloads"),
            .folder("  "),
            .folder(" /Users/x/Documents "),
        ]
        #expect(
            entries.repaired(capacity: 9) == [
                .folder("/Users/x/Downloads"),
                .application("com.apple.Safari"),
                .folder("/Users/x/Documents"),
            ]
        )
    }

    @Test("Version 5 has a migration from 4, so a v4 dock is not quarantined")
    func migratesFromVersionFour() throws {
        var stored = NexusConfiguration()
        stored.version = 4
        stored.pinnedEntries = [.application("com.apple.Safari")]
        let defaults = UserDefaults(suiteName: "nexus.folder.test.\(UUID().uuidString)")!
        defaults.set(try JSONEncoder().encode(stored), forKey: "configuration")
        let store = ConfigurationStore(defaults: defaults)

        let loaded = store.load()
        #expect(loaded.version == NexusConfiguration.currentVersion)
        #expect(loaded.pinnedEntries == [.application("com.apple.Safari")])
        if case .corruptQuarantined = store.outcomeOfLastLoad {
            Issue.record("A v4 dock was quarantined instead of migrated")
        }
    }
}
