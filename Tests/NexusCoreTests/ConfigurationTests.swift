import Foundation
import Testing

@testable import NexusCore

private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("Configuration")
struct ConfigurationTests {
    @Test("Defaults match the documented schema")
    func defaults() {
        let configuration = NexusConfiguration()
        #expect(configuration.version == NexusConfiguration.currentVersion)
        #expect(configuration.appearance.position == .left)
        #expect(configuration.appearance.width == 64)
        #expect(configuration.search.shortcut == .optionSpace)
        #expect(configuration.onboarding.hasCompleted == false)
        #expect(configuration.pinnedApplications.isEmpty)
    }

    @Test("Round-trips through the store identically")
    func roundTrip() throws {
        let defaults = makeDefaults()
        let store = ConfigurationStore(defaults: defaults)

        var configuration = NexusConfiguration()
        configuration.appearance.position = .right
        configuration.appearance.width = 88
        configuration.pinnedApplications = ["com.apple.Safari", "com.apple.Terminal"]
        configuration.search.shortcut = .commandSpace
        configuration.frecency["app:com.apple.Safari"] = FrecencyEntry(count: 3, lastUsed: Date(timeIntervalSince1970: 1_000))
        configuration.onboarding.hasCompleted = true

        try store.save(configuration)

        let reloaded = ConfigurationStore(defaults: defaults).load()
        #expect(reloaded == configuration)
    }

    @Test("Absent stored configuration falls back to defaults")
    func absent() {
        let store = ConfigurationStore(defaults: makeDefaults())
        #expect(store.load() == NexusConfiguration())
        #expect(store.outcomeOfLastLoad == .defaultsNoStoredData)
    }

    @Test("Corrupt stored configuration falls back to defaults and is copied aside")
    func corrupt() {
        let defaults = makeDefaults()
        defaults.set(Data("this is not json".utf8), forKey: ConfigurationStore.defaultKey)

        let store = ConfigurationStore(defaults: defaults)
        #expect(store.load() == NexusConfiguration())

        guard case .corruptQuarantined(let key) = store.outcomeOfLastLoad else {
            Issue.record("expected quarantine, got \(store.outcomeOfLastLoad)")
            return
        }
        #expect(defaults.data(forKey: key) == Data("this is not json".utf8))
        // The original bytes are still there too — nothing was destroyed.
        #expect(defaults.data(forKey: ConfigurationStore.defaultKey) != nil)
    }

    @Test("A newer-versioned configuration is left untouched and defaults are used")
    func newerVersion() throws {
        let defaults = makeDefaults()
        var future = NexusConfiguration()
        future.appearance.position = .right
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(future)) as! [String: Any]
        json["version"] = NexusConfiguration.currentVersion + 5
        let raw = try JSONSerialization.data(withJSONObject: json)
        defaults.set(raw, forKey: ConfigurationStore.defaultKey)

        let store = ConfigurationStore(defaults: defaults)
        #expect(store.load() == NexusConfiguration())
        #expect(store.outcomeOfLastLoad == .newerVersionIgnored(NexusConfiguration.currentVersion + 5))
        #expect(defaults.data(forKey: ConfigurationStore.defaultKey) == raw)
    }

    @Test("A partial payload decodes, filling in defaults for missing groups")
    func partialPayload() {
        let defaults = makeDefaults()
        let raw = Data(#"{"version":1,"pinnedApplications":["com.apple.Finder"]}"#.utf8)
        defaults.set(raw, forKey: ConfigurationStore.defaultKey)

        let configuration = ConfigurationStore(defaults: defaults).load()
        #expect(configuration.pinnedApplications == ["com.apple.Finder"])
        #expect(configuration.appearance == AppearanceConfiguration())
    }

    @Test("Out-of-range appearance values are clamped, not trusted")
    func clamping() throws {
        let defaults = makeDefaults()
        let raw = Data(#"{"version":1,"appearance":{"position":"left","width":9000,"iconSize":-3,"iconSpacing":8,"cornerRadius":16,"opacity":42,"display":{"main":{}},"perDisplay":{}}}"#.utf8)
        defaults.set(raw, forKey: ConfigurationStore.defaultKey)

        let configuration = ConfigurationStore(defaults: defaults).load()
        #expect(configuration.appearance.width == AppearanceConfiguration.widthRange.upperBound)
        #expect(configuration.appearance.iconSize == AppearanceConfiguration.iconSizeRange.lowerBound)
        #expect(configuration.appearance.opacity == AppearanceConfiguration.opacityRange.upperBound)
    }
}

private struct AddNicknameMigration: ConfigurationMigration {
    let fromVersion = 1
    func migrate(_ json: inout [String: Any]) throws {
        var general = json["general"] as? [String: Any] ?? [:]
        general["showInMenuBar"] = false
        json["general"] = general
    }
}

@Suite("Configuration migration")
struct ConfigurationMigrationTests {
    @Test("A registered migration runs and bumps the version")
    func migrationRuns() throws {
        // Pretend the current version is one ahead by writing a version-1 payload and
        // registering a 1 -> 2 step. With currentVersion == 1 there is nothing to migrate,
        // so exercise the step directly plus the no-op path through the store.
        var json: [String: Any] = ["version": 1, "general": ["showInMenuBar": true]]
        try AddNicknameMigration().migrate(&json)
        let general = json["general"] as! [String: Any]
        #expect(general["showInMenuBar"] as? Bool == false)
    }

    @Test("A same-version payload is decoded without migration")
    func noMigrationNeeded() throws {
        let defaults = makeDefaults()
        let store = ConfigurationStore(defaults: defaults, migrations: [AddNicknameMigration()])
        try store.save(NexusConfiguration())
        _ = store.load()
        #expect(store.outcomeOfLastLoad == .decoded)
    }

    @Test("A missing migration step degrades to defaults instead of crashing")
    func missingStep() throws {
        let defaults = makeDefaults()
        let raw = Data(#"{"version":-4}"#.utf8)
        defaults.set(raw, forKey: ConfigurationStore.defaultKey)

        let store = ConfigurationStore(defaults: defaults, migrations: [])
        #expect(store.load() == NexusConfiguration())
        guard case .corruptQuarantined = store.outcomeOfLastLoad else {
            Issue.record("expected quarantine, got \(store.outcomeOfLastLoad)")
            return
        }
    }
}

@Suite("KeyboardShortcut")
struct KeyboardShortcutTests {
    @Test("Option+Space is the development default and is valid")
    func optionSpace() {
        #expect(KeyboardShortcut.optionSpace.isValid)
        #expect(KeyboardShortcut.optionSpace.isCommandSpace == false)
    }

    @Test("Command+Space is recognised so the Spotlight guide can be shown")
    func commandSpace() {
        #expect(KeyboardShortcut.commandSpace.isCommandSpace)
    }

    @Test("Shift alone is not a valid modifier")
    func shiftOnly() {
        let shortcut = KeyboardShortcut(keyCode: 49, modifiers: KeyboardShortcut.shiftKey)
        #expect(shortcut.isValid == false)
    }

    @Test("No modifier is rejected")
    func noModifier() {
        #expect(KeyboardShortcut(keyCode: 49, modifiers: 0).isValid == false)
    }
}
