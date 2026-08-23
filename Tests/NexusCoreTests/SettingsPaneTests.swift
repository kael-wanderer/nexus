import Foundation
import NexusCore
import Testing

@testable import NexusCore

/// Builds a fake `Extensions` directory, so the parsing tests do not depend on which macOS this is.
private struct FakeExtensions: ~Copyable {
    let root: URL
    let panes: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nexus-panes-\(UUID().uuidString)")
        panes = root.appendingPathComponent("PreferencePanes")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: panes, withIntermediateDirectories: true)
    }

    func extensionBundle(
        _ name: String,
        displayName: String?,
        legacyIdentifier: Any?,
        legacyPane: String? = nil,
        allowsURLScheme: Bool = true
    ) throws {
        var attributes: [String: Any] = ["allowsXAppleSystemPreferencesURLScheme": allowsURLScheme]
        if let legacyIdentifier { attributes["legacyBundleIdentifier"] = legacyIdentifier }
        if let legacyPane { attributes["legacyPrefPaneBundleName"] = legacyPane }
        var info: [String: Any] = [
            "EXAppExtensionAttributes": ["SettingsExtensionAttributes": attributes],
        ]
        if let displayName { info["CFBundleDisplayName"] = displayName }
        try write(info, to: root.appendingPathComponent("\(name).appex"))
    }

    func legacyPane(_ name: String, bundleName: String) throws {
        try write(["CFBundleName": bundleName], to: panes.appendingPathComponent(name))
    }

    private func write(_ info: [String: Any], to bundle: URL) throws {
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: info, format: .xml, options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

@Suite("System Settings panes")
struct SettingsPaneTests {
    @Test("A pane is its legacy identifier and a name, and it opens through the URL scheme")
    func readsPanes() throws {
        let fake = try FakeExtensions()
        try fake.extensionBundle(
            "DisplaysExt", displayName: "Displays", legacyIdentifier: "com.apple.preference.displays"
        )
        let panes = SettingsPaneIndex.panes(in: fake.root, legacyPanes: fake.panes)

        #expect(panes.map(\.name) == ["Displays"])
        #expect(panes[0].id == "com.apple.preference.displays")
        #expect(panes[0].url?.absoluteString == "x-apple.systempreferences:com.apple.preference.displays")
    }

    @Test("The legacy pane's own name wins over a developer's bundle name")
    func legacyNameWins() throws {
        let fake = try FakeExtensions()
        try fake.legacyPane("UniversalAccessPref.prefPane", bundleName: "Accessibility")
        try fake.extensionBundle(
            "AccessibilitySettingsExtension",
            displayName: "AccessibilitySettingsExtension",
            legacyIdentifier: "com.apple.preference.universalaccess",
            legacyPane: "UniversalAccessPref.prefPane"
        )
        #expect(SettingsPaneIndex.panes(in: fake.root, legacyPanes: fake.panes).map(\.name) == ["Accessibility"])
    }

    @Test("An extension that does not take the URL scheme is not a result")
    func skipsUnopenablePanes() throws {
        let fake = try FakeExtensions()
        try fake.extensionBundle(
            "Widget", displayName: "Widget", legacyIdentifier: "com.apple.widget",
            allowsURLScheme: false
        )
        try fake.extensionBundle("Sound", displayName: "Sound", legacyIdentifier: "com.apple.preference.sound")
        #expect(SettingsPaneIndex.panes(in: fake.root, legacyPanes: fake.panes).map(\.name) == ["Sound"])
    }

    @Test("An extension with no identifier at all is skipped rather than half-drawn")
    func skipsIdentifierless() throws {
        let fake = try FakeExtensions()
        try fake.extensionBundle("Mystery", displayName: "Mystery", legacyIdentifier: nil)
        #expect(SettingsPaneIndex.panes(in: fake.root, legacyPanes: fake.panes).isEmpty)
    }

    @Test("Two identifiers means the first one, which is the one System Settings opens")
    func arrayIdentifier() throws {
        let fake = try FakeExtensions()
        try fake.extensionBundle(
            "PowerPreferences",
            displayName: "PowerPreferences",
            legacyIdentifier: ["com.apple.preference.battery", "com.apple.preferences.EnergySaverPrefPane"]
        )
        let panes = SettingsPaneIndex.panes(in: fake.root, legacyPanes: fake.panes)
        #expect(panes.map(\.id) == ["com.apple.preference.battery"])
        #expect(panes.map(\.name) == ["Power Preferences"])
    }

    @Test("The same pane behind two extensions appears once")
    func deduplicates() throws {
        let fake = try FakeExtensions()
        try fake.extensionBundle("A", displayName: "Sound", legacyIdentifier: "com.apple.preference.sound")
        try fake.extensionBundle("B", displayName: "Sound Again", legacyIdentifier: "com.apple.preference.sound")
        #expect(SettingsPaneIndex.panes(in: fake.root, legacyPanes: fake.panes).count == 1)
    }

    @Test("Bundle names are tidied into titles")
    func names() {
        #expect(SettingsPaneIndex.displayName(bundleName: "MouseExtension", legacyName: nil) == "Mouse")
        #expect(SettingsPaneIndex.displayName(bundleName: "DateAndTime Extension", legacyName: nil) == "Date And Time")
        #expect(SettingsPaneIndex.displayName(bundleName: "Displays", legacyName: nil) == "Displays")
        #expect(SettingsPaneIndex.displayName(bundleName: "Screen Time", legacyName: nil) == "Screen Time")
        #expect(SettingsPaneIndex.displayName(bundleName: "AppleIDSettings", legacyName: "Apple Account") == "Apple Account")
        #expect(SettingsPaneIndex.displayName(bundleName: nil, legacyName: nil) == nil)
        #expect(SettingsPaneIndex.splitCamelCase("DateAndTime") == "Date And Time")
    }

    /// Against the machine this runs on, which is the only way to know the shape of the real
    /// directory has not moved. Skipped where there is no such directory.
    @Test("The real system has panes, and the ones everybody has are in it")
    func readsTheRealSystem() throws {
        try #require(FileManager.default.fileExists(atPath: SettingsPaneIndex.extensionsDirectory.path))
        let panes = SettingsPaneIndex.panes()
        #expect(panes.count > 10)
        let names = Set(panes.map(\.name))
        #expect(names.contains("Displays"))
        #expect(names.contains("Keyboard"))
        #expect(panes.allSatisfy { $0.url != nil })
    }
}

@Suite("Settings panes as results")
struct SettingsPaneSearchTests {
    private func provider(_ panes: [SettingsPane]) -> ActionSearchProvider {
        ActionSearchProvider(runningApplications: { [] }, settingsPanes: { panes })
    }

    private let context = SearchContext()

    @Test("Typing a pane's name finds it, and running it opens the settings URL")
    func findsPane() async {
        let panes = [SettingsPane(id: "com.apple.preference.displays", name: "Displays")]
        let results = await provider(panes).results(
            for: SearchQuery(text: "displ", token: 1), context: context
        )
        let pane = results.first { $0.title == "Displays" }
        #expect(pane != nil)
        #expect(pane?.subtitle == "System Settings")
        #expect(pane?.action == .openURL(URL(string: "x-apple.systempreferences:com.apple.preference.displays")!))
    }

    @Test("A pane nobody typed does not turn up")
    func filtersPanes() async {
        let panes = [SettingsPane(id: "com.apple.preference.sound", name: "Sound")]
        let results = await provider(panes).results(
            for: SearchQuery(text: "zzzz", token: 1), context: context
        )
        #expect(results.isEmpty)
    }

    @Test("Built-in actions keep their own subtitle")
    func actionsKeepTheirSubtitle() async {
        let results = await provider([]).results(
            for: SearchQuery(text: "lock", token: 1), context: context
        )
        #expect(results.contains { $0.subtitle == "Action" })
    }

    @Test("The Settings scope is honest about holding both")
    func scopeTitle() {
        #expect(SearchScope.settings.title == "Settings & Actions")
        #expect(SearchScope.settings.providers == [.action])
    }
}

