import Foundation
import Testing

@testable import NexusCore

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

    @Test("The default switcher shortcut is option-tab")
    func defaultIsOptionTab() {
        #expect(KeyboardShortcut.windowSwitcherDefault == KeyboardShortcut(keyCode: 48, modifiers: KeyboardShortcut.optionKey))
        #expect(GeneralConfiguration().windowSwitcherShortcut == .windowSwitcherDefault)
    }

    @Test("A stored control-option-W is kept")
    func storedControlOptionWIsKept() throws {
        let json = Data("""
        {"windowSwitcherShortcut": {"keyCode": 13, "modifiers": 6144}}
        """.utf8)
        let general = try JSONDecoder().decode(GeneralConfiguration.self, from: json)
        #expect(general.windowSwitcherShortcut == KeyboardShortcut(keyCode: 13, modifiers: KeyboardShortcut.controlKey | KeyboardShortcut.optionKey))
    }

    @Test("A stored null keeps the switcher off")
    func storedNullKeepsSwitcherOff() throws {
        let json = Data("""
        {"windowSwitcherShortcut": null}
        """.utf8)
        let general = try JSONDecoder().decode(GeneralConfiguration.self, from: json)
        #expect(general.windowSwitcherShortcut == nil)
    }

    @Test("A configuration with no switcher key gets the default")
    func absentKeyGetsDefault() throws {
        let general = try JSONDecoder().decode(GeneralConfiguration.self, from: Data("{}".utf8))
        #expect(general.windowSwitcherShortcut == .windowSwitcherDefault)
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

    @Test("A stored sort survives a round trip; an unknown value is dropped, not fatal")
    func folderSortDecode() throws {
        let json = Data("""
        {"autoHide": true, "folderSort": {"/a": "dateAdded", "/b": "bySize"}}
        """.utf8)
        let behavior = try JSONDecoder().decode(BehaviorConfiguration.self, from: json)
        #expect(behavior.autoHide == true)
        #expect(behavior.folderSort == ["/a": .dateAdded])

        let again = try JSONDecoder().decode(BehaviorConfiguration.self, from: JSONEncoder().encode(behavior))
        #expect(again.folderSort == ["/a": .dateAdded])
    }

    @Test("A configuration written before this key existed still loads")
    func folderSortAbsent() throws {
        let behavior = try JSONDecoder().decode(BehaviorConfiguration.self, from: Data("{}".utf8))
        #expect(behavior.folderSort == [:])
        #expect(NexusConfiguration.currentVersion == 5)

        let defaults = makeDefaults()
        let store = ConfigurationStore(defaults: defaults)
        var configuration = NexusConfiguration()
        configuration.behavior.folderSort["/a"] = .dateAdded
        try store.save(configuration)
        #expect(ConfigurationStore(defaults: defaults).load().behavior.folderSort == ["/a": .dateAdded])
    }

    @Test("A folder's sort is the stored one, else the default for its path")
    func folderSortLookup() {
        var behavior = BehaviorConfiguration()
        behavior.folderSort["/Users/x/Documents"] = .dateAdded
        #expect(behavior.sort(forFolder: "/Users/x/Documents") == .dateAdded)
        #expect(behavior.sort(forFolder: "/Users/x/Other") == .name)
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

    /// D10 is only kept if nothing writes afterwards: `Composition.start()` flushes on launch,
    /// every edit schedules a save, and terminate flushes again.
    @Test("A newer-versioned configuration survives the launch flush, an edit and the quit flush")
    @MainActor
    func newerVersionSurvivesWrites() async throws {
        let defaults = makeDefaults()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(NexusConfiguration())) as! [String: Any]
        json["version"] = NexusConfiguration.currentVersion + 1
        let raw = try JSONSerialization.data(withJSONObject: json)
        defaults.set(raw, forKey: ConfigurationStore.defaultKey)

        let store = ConfigurationStore(defaults: defaults)
        let controller = ConfigurationController(store: store, events: EventBus(), saveDelay: .milliseconds(10))

        controller.flush()
        #expect(defaults.data(forKey: ConfigurationStore.defaultKey) == raw)

        controller.update { $0.appearance.position = .bottom }
        try await Task.sleep(for: .milliseconds(100))
        #expect(defaults.data(forKey: ConfigurationStore.defaultKey) == raw)
        // The edit still applies for this session — it just is not written over the newer file.
        #expect(controller.configuration.appearance.position == .bottom)

        controller.flush()
        #expect(defaults.data(forKey: ConfigurationStore.defaultKey) == raw)
    }

    @Test("With nothing stored, the launch flush still writes the defaults")
    @MainActor
    func firstLaunchStillWrites() throws {
        let defaults = makeDefaults()
        let controller = ConfigurationController(store: ConfigurationStore(defaults: defaults), events: EventBus())
        controller.flush()
        let data = try #require(defaults.data(forKey: ConfigurationStore.defaultKey))
        #expect(try JSONDecoder().decode(NexusConfiguration.self, from: data) == NexusConfiguration())
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
    @Test("A migration step rewrites the payload it is handed")
    func migrationStepRewritesPayload() throws {
        // The step on its own. The real chain through the store — a stored older version
        // loading as the current one — is covered by `migratesFromVersionFour`.
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

    /// Only appearance was clamped on the way in. An out-of-range behaviour value was stored as
    /// written and then silently changed by the next launch's decode.
    @MainActor
    @Test("An out-of-range behaviour value is clamped when it is set, not at the next launch")
    func behaviorIsClampedOnUpdate() {
        let controller = ConfigurationController(
            store: InMemoryConfigurationStore(),
            events: EventBus(),
            saveDelay: .zero
        )

        controller.update {
            $0.behavior.autoHideDelay = 99
            $0.behavior.groupCapacity = 7
        }

        #expect(controller.configuration.behavior.autoHideDelay == 5)
        #expect(controller.configuration.behavior.groupCapacity == 9)
    }

    @MainActor
    @Test("Recording a use is saved but not announced; a real setting change is")
    func usageIsNotAnnounced() async throws {
        let events = EventBus()
        let controller = ConfigurationController(
            store: InMemoryConfigurationStore(),
            events: events,
            saveDelay: .zero
        )
        var iterator = events.events().makeAsyncIterator()

        controller.update { $0.recordUse(of: "app:com.apple.Safari") }
        #expect(controller.configuration.frecency["app:com.apple.Safari"]?.count == 1)

        // The next event on the bus is the setting change, so the usage bump published nothing.
        controller.update { $0.general.showStartMenu = true }
        guard case .configurationChanged(let announced) = await iterator.next() else {
            Issue.record("Expected a configuration change")
            return
        }
        #expect(announced.general.showStartMenu)
        #expect(announced.frecency["app:com.apple.Safari"]?.count == 1)
    }

    @Test("Usage is remembered for a bounded number of results, the most recent ones")
    func usageIsBounded() {
        var configuration = NexusConfiguration()
        let start = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<(NexusConfiguration.frecencyLimit + 25) {
            configuration.recordUse(of: "file:\(index)", at: start.addingTimeInterval(Double(index)))
        }

        #expect(configuration.frecency.count == NexusConfiguration.frecencyLimit)
        #expect(configuration.frecency["file:0"] == nil)                     // oldest: forgotten
        #expect(configuration.frecency["file:24"] == nil)
        #expect(configuration.frecency["file:25"] != nil)
        #expect(configuration.frecency["file:\(NexusConfiguration.frecencyLimit + 24)"]?.count == 1)

        // Using an old one again makes it recent, so it is not the next to go.
        configuration.recordUse(of: "file:25", at: start.addingTimeInterval(10_000))
        configuration.recordUse(of: "file:new", at: start.addingTimeInterval(10_001))
        #expect(configuration.frecency["file:25"]?.count == 2)
        #expect(configuration.frecency["file:26"] == nil)
    }
}
