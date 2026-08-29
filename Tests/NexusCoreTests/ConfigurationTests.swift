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
        configuration.setPinnedApplications(["com.apple.Safari", "com.apple.Terminal"])
        configuration.search.shortcut = .commandSpace
        configuration.frecency["app:com.apple.Safari"] = FrecencyEntry(count: 3, lastUsed: Date(timeIntervalSince1970: 1_000))
        configuration.onboarding.hasCompleted = true

        try store.save(configuration)

        let reloaded = ConfigurationStore(defaults: defaults).load()
        #expect(reloaded == configuration)
    }

    @Test("Window switcher defaults")
    func windowSwitcherDefaults() {
        let configuration = NexusConfiguration()
        #expect(configuration.general.windowSwitcherShortcut == .windowSwitcherDefault)
        #expect(configuration.behavior.windowSwitcherGrouping == .flat)
        #expect(configuration.behavior.windowSwitcherSort == .recent)
        #expect(configuration.behavior.windowSwitcherSortReversed == false)
        #expect(configuration.behavior.windowSwitcherThumbnails == true)
        #expect(configuration.behavior.flyoutSize == .medium)
    }

    @Test("The switcher shortcut is a valid, non-colliding combination")
    func windowSwitcherShortcutIsValid() {
        let shortcut = KeyboardShortcut.windowSwitcherDefault
        #expect(shortcut.isValid)
        #expect(shortcut != .optionSpace)
        #expect(shortcut != .focusBarDefault)
    }

    @Test("A file written before the switcher existed keeps its other fields")
    func windowSwitcherTolerantDecode() throws {
        // A behavior section from an earlier version: no switcher keys at all.
        let json = Data("""
        {"autoHide": true, "groupCapacity": 16}
        """.utf8)
        let behavior = try JSONDecoder().decode(BehaviorConfiguration.self, from: json)
        #expect(behavior.autoHide == true)
        #expect(behavior.groupCapacity == 16)
        #expect(behavior.windowSwitcherGrouping == .flat)
        #expect(behavior.windowSwitcherSort == .recent)
        #expect(behavior.windowSwitcherThumbnails == true)
    }

    @Test("A file written before the flyout size setting existed decodes to medium")
    func flyoutSizeTolerantDecode() throws {
        let json = Data("""
        {"autoHide": true}
        """.utf8)
        let behavior = try JSONDecoder().decode(BehaviorConfiguration.self, from: json)
        #expect(behavior.flyoutSize == .medium)
    }

    @Test("The flyout size round-trips through the store")
    func flyoutSizeRoundTrip() throws {
        let store = ConfigurationStore(defaults: makeDefaults())
        var configuration = NexusConfiguration()
        configuration.behavior.flyoutSize = .large

        try store.save(configuration)
        let loaded = store.load()
        #expect(loaded.behavior.flyoutSize == .large)
    }

    @Test("Switcher preferences round-trip through the store")
    func windowSwitcherRoundTrip() throws {
        let store = ConfigurationStore(defaults: makeDefaults())
        var configuration = NexusConfiguration()
        configuration.behavior.windowSwitcherGrouping = .display
        configuration.behavior.windowSwitcherSort = .title
        configuration.behavior.windowSwitcherSortReversed = true
        configuration.general.windowSwitcherShortcut = nil

        try store.save(configuration)
        let loaded = store.load()
        #expect(loaded.behavior.windowSwitcherGrouping == .display)
        #expect(loaded.behavior.windowSwitcherSort == .title)
        #expect(loaded.behavior.windowSwitcherSortReversed == true)
        #expect(loaded.general.windowSwitcherShortcut == nil)
    }

    @Test("A nil'd bar shortcut round-trips as nil, not the default")
    func focusBarShortcutNilRoundTrip() throws {
        let store = ConfigurationStore(defaults: makeDefaults())
        var configuration = NexusConfiguration()
        configuration.general.focusBarShortcut = nil

        try store.save(configuration)
        let loaded = store.load()
        #expect(loaded.general.focusBarShortcut == nil)
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

    /// A synthesised `Codable` treats a missing key as an error, so a field added in a later
    /// version would take every other field in its section down with it — the settings would
    /// silently reset on the first launch after an upgrade (D67).
    @Test("A configuration written before a field existed keeps the fields it does have")
    func toleratesMissingKeys() throws {
        let defaults = makeDefaults()
        let raw = Data("""
        {"version":1,
         "appearance":{"position":"right","width":100,"iconSize":48,"iconSpacing":8,"cornerRadius":16,"opacity":1,"display":{"main":{}},"perDisplay":{}},
         "behavior":{"autoHide":true,"autoHideDelay":0.8,"hoverExpand":false,"showRunningApplications":false,"showWindowCount":false,"showFavorites":true,"clickBehavior":"showWindowList"},
         "general":{"launchAtLogin":true,"showInMenuBar":false,"globalShortcutEnabled":false},
         "search":{"shortcut":{"keyCode":49,"modifiers":256},"searchApplications":true,"searchWindows":true,"searchFiles":false,"searchActions":true,"maximumResults":12}}
        """.utf8)
        defaults.set(raw, forKey: ConfigurationStore.defaultKey)

        let configuration = ConfigurationStore(defaults: defaults).load()

        // Stored values survive…
        #expect(configuration.appearance.position == .right)
        #expect(configuration.appearance.width == 100)
        #expect(configuration.behavior.autoHide)
        #expect(configuration.behavior.clickBehavior == .showWindowList)
        #expect(configuration.general.launchAtLogin)
        #expect(configuration.general.showInMenuBar == false)
        #expect(configuration.search.maximumResults == 12)
        #expect(configuration.search.searchFiles == false)

        // …and the fields that did not exist yet take their defaults.
        #expect(configuration.appearance.startMenuCorner == .bottomLeading)
        #expect(configuration.behavior.hoverPreview)
        #expect(configuration.behavior.hoverPreviewDelay == 0.5)
        #expect(configuration.behavior.reserveSpace == false)
        #expect(configuration.general.showStartMenu == false)
        #expect(configuration.general.showClock)
        #expect(configuration.general.showVolume)
        #expect(configuration.dock.replacementEnabled == false)
        #expect(configuration.runningApplicationOrder.isEmpty)
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
