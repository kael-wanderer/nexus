import Foundation
import Testing

@testable import NexusCore

private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("Dock entries")
struct DockEntryTests {
    @Test("A dock of applications and groups round-trips through JSON")
    func roundTrip() throws {
        let group = ApplicationGroup(name: "Developer", applications: ["com.apple.Terminal", "com.apple.dt.Xcode"])
        let entries: [DockEntry] = [.application("com.apple.Safari"), .group(group)]

        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([DockEntry].self, from: data)
        #expect(decoded == entries)

        // Legible in `defaults read`, which is the reason for the hand-written coding keys.
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        #expect(json[0]["application"] as? String == "com.apple.Safari")
        #expect((json[1]["group"] as? [String: Any])?["name"] as? String == "Developer")
    }

    @Test("An over-full group keeps its first members, and the capacity setting decides how many")
    func overFull() {
        let members = (1...12).map { "app.\($0)" }
        let entries: [DockEntry] = [.group(ApplicationGroup(name: "Big", applications: members))]

        #expect(entries.repaired(capacity: 9)[0].applications.count == 9)
        #expect(entries.repaired(capacity: 16)[0].applications == members)
    }

    @Test("A group of one becomes that application, and an empty group disappears")
    func dissolves() {
        let entries: [DockEntry] = [
            .group(ApplicationGroup(name: "One", applications: ["a"])),
            .group(ApplicationGroup(name: "None", applications: [])),
            .application("b"),
        ]
        #expect(entries.repaired(capacity: 9) == [.application("a"), .application("b")])
    }

    @Test("An application listed twice keeps its first slot, wherever that is")
    func duplicates() {
        let entries: [DockEntry] = [
            .application("a"),
            .group(ApplicationGroup(name: "Group", applications: ["a", "b", "c"])),
            .application("b"),
        ]
        let repaired = entries.repaired(capacity: 9)
        #expect(repaired.count == 2)
        #expect(repaired[0] == .application("a"))
        #expect(repaired[1].group?.applications == ["b", "c"])
    }

    @Test("A group is found by the application it holds")
    func indexContaining() {
        let entries: [DockEntry] = [
            .application("a"),
            .group(ApplicationGroup(name: "Group", applications: ["b", "c"])),
        ]
        #expect(entries.index(containing: "c") == 1)
        #expect(entries.index(containing: "zzz") == nil)
    }
}

@Suite("Configuration version 2")
struct PinnedEntriesMigrationTests {
    @Test("A version 1 dock migrates to version 2 with the same applications in the same order")
    func migrates() throws {
        let defaults = makeDefaults()
        let raw = Data("""
        {"version":1,
         "pinnedApplications":["com.apple.Safari","com.apple.Terminal","com.apple.Music"],
         "appearance":{"position":"right","width":72,"iconSize":40,"iconSpacing":8,"cornerRadius":16,"opacity":1,"display":{"main":{}},"perDisplay":{}}}
        """.utf8)
        defaults.set(raw, forKey: ConfigurationStore.defaultKey)

        let store = ConfigurationStore(defaults: defaults)
        let configuration = store.load()

        #expect(store.outcomeOfLastLoad == .migrated(from: 1))
        #expect(configuration.pinnedApplications == ["com.apple.Safari", "com.apple.Terminal", "com.apple.Music"])
        #expect(configuration.pinnedEntries.allSatisfy { $0.group == nil })
        // Version 3 runs on top of it: the row limits arrive as "fit the screen".
        #expect(configuration.appearance.pinnedLimit == 0)
        #expect(configuration.appearance.runningLimit == 0)
        // Nothing else about the dock changed.
        #expect(configuration.appearance.position == .right)
        #expect(configuration.appearance.width == 72)
        // And the original bytes are still there: a migration reads, it does not destroy (D10).
        #expect(defaults.data(forKey: ConfigurationStore.defaultKey) == raw)
    }

    @Test("Saving keeps writing the version 1 key, so a downgrade still finds the dock")
    func writesLegacyKey() throws {
        let defaults = makeDefaults()
        var configuration = NexusConfiguration()
        configuration.pinnedEntries = [
            .application("com.apple.Safari"),
            .group(ApplicationGroup(name: "Developer", applications: ["com.apple.Terminal", "com.apple.dt.Xcode"])),
        ]
        try ConfigurationStore(defaults: defaults).save(configuration)

        let json = try JSONSerialization.jsonObject(
            with: defaults.data(forKey: ConfigurationStore.defaultKey)!
        ) as! [String: Any]
        #expect(json["version"] as? Int == NexusConfiguration.currentVersion)
        #expect(
            json["pinnedApplications"] as? [String]
                == ["com.apple.Safari", "com.apple.Terminal", "com.apple.dt.Xcode"]
        )
    }

    @Test("A current-version payload with only the old key still finds its dock")
    func legacyKeyOnly() {
        let defaults = makeDefaults()
        let raw = Data(#"{"version":3,"pinnedApplications":["com.apple.Finder"]}"#.utf8)
        defaults.set(raw, forKey: ConfigurationStore.defaultKey)

        let configuration = ConfigurationStore(defaults: defaults).load()
        #expect(configuration.pinnedEntries == [.application("com.apple.Finder")])
    }

    @Test("A stored group that is over capacity, empty or duplicated is repaired on load")
    func repairedOnLoad() throws {
        let defaults = makeDefaults()
        let members = (1...12).map { "\"app.\($0)\"" }.joined(separator: ",")
        let raw = Data("""
        {"version":3,"pinnedEntries":[
          {"group":{"id":"\(UUID().uuidString)","name":"Big","applications":[\(members)]}},
          {"group":{"id":"\(UUID().uuidString)","name":"Empty","applications":[]}},
          {"application":"app.1"}
        ]}
        """.utf8)
        defaults.set(raw, forKey: ConfigurationStore.defaultKey)

        let configuration = ConfigurationStore(defaults: defaults).load()
        #expect(configuration.pinnedEntries.count == 1)
        #expect(configuration.pinnedEntries[0].group?.applications.count == 9)
    }

    @Test("An unusable group capacity falls back to nine rather than being trusted")
    func capacityClamped() {
        let defaults = makeDefaults()
        let raw = Data(#"{"version":3,"behavior":{"groupCapacity":400}}"#.utf8)
        defaults.set(raw, forKey: ConfigurationStore.defaultKey)
        #expect(ConfigurationStore(defaults: defaults).load().behavior.groupCapacity == 9)
    }
}

@Suite("Group names")
struct ApplicationCategoryTests {
    @Test("A category identifier becomes a word")
    func displayNames() {
        #expect(ApplicationCategory.displayName(for: "public.app-category.developer-tools") == "Developer")
        #expect(ApplicationCategory.displayName(for: "public.app-category.social-networking") == "Social")
        // Unknown categories still read as words rather than as identifiers.
        #expect(ApplicationCategory.displayName(for: "public.app-category.action-games") == "Action Games")
        #expect(ApplicationCategory.displayName(for: "com.example.whatever") == nil)
    }

    @Test("A group takes the category most of its members declare")
    func majority() {
        let name = ApplicationCategory.groupName(for: [
            "public.app-category.developer-tools",
            "public.app-category.developer-tools",
            "public.app-category.social-networking",
        ])
        #expect(name == "Developer")
    }

    @Test("Members that agree on nothing, or declare nothing, make a Group")
    func fallback() {
        #expect(ApplicationCategory.groupName(for: [nil, nil]) == "Group")
        #expect(ApplicationCategory.groupName(for: ["not.a.category"]) == "Group")
        // A tie goes to the first category in member order, so the name is not luck.
        let tie = ApplicationCategory.groupName(for: [
            "public.app-category.utilities",
            "public.app-category.developer-tools",
        ])
        #expect(tie == "Utilities")
    }
}

@Suite("Automatic row limits")
struct AutomaticRowLimitsMigrationTests {
    /// The version that shipped the limits wrote 10 and 5 as *the* number of rows. They now mean a
    /// ceiling, and the bar is meant to fill the screen it has — so a stored pair from that build
    /// is dropped rather than kept capping a half-empty bar.
    @Test("A version 2 configuration comes back with both limits set to fit the screen")
    func resetsShippedDefaults() {
        let defaults = makeDefaults()
        let raw = Data("""
        {"version":2,
         "appearance":{"position":"left","width":64,"iconSize":40,"iconSpacing":8,"cornerRadius":16,
                       "opacity":1,"display":{"main":{}},"perDisplay":{},
                       "pinnedLimit":10,"runningLimit":5}}
        """.utf8)
        defaults.set(raw, forKey: ConfigurationStore.defaultKey)

        let store = ConfigurationStore(defaults: defaults)
        let configuration = store.load()

        #expect(store.outcomeOfLastLoad == .migrated(from: 2))
        #expect(configuration.appearance.pinnedLimit == 0)
        #expect(configuration.appearance.runningLimit == 0)
        // Version 4 runs on top of it: the previous default icon size becomes a Dock-sized one.
        #expect(configuration.appearance.iconSize == 64)
    }

    @Test("A ceiling set against the new meaning is kept")
    func keepsDeliberateCeiling() throws {
        let defaults = makeDefaults()
        var configuration = NexusConfiguration()
        configuration.appearance.runningLimit = 6
        try ConfigurationStore(defaults: defaults).save(configuration)

        #expect(ConfigurationStore(defaults: defaults).load().appearance.runningLimit == 6)
    }
}

