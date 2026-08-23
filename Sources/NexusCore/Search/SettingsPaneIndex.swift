import Foundation

/// One pane of System Settings, as something the palette can open (M19's Settings scope, finished).
public struct SettingsPane: Sendable, Equatable, Identifiable {
    /// The legacy preference-pane identifier, which is what the URL scheme takes.
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// `x-apple.systempreferences:` is the documented way to open a pane, and the extensions that
    /// accept it say so in their own `Info.plist`.
    public var url: URL? { URL(string: "x-apple.systempreferences:\(id)") }
}

/// Where the panes come from, and what they are called.
///
/// System Settings has been a set of ExtensionKit extensions since macOS 13, so there is no
/// Spotlight answer to "what panes exist" — `kMDItemContentTypeTree == public.prefpane` returns
/// nothing on a modern system, because the panes on the sealed system volume are not indexed. What
/// does exist is the extension directory, and each extension's `Info.plist` carries the two things
/// worth having: the legacy identifier the URL scheme takes, and a name.
public enum SettingsPaneIndex {
    public static let extensionsDirectory = URL(
        fileURLWithPath: "/System/Library/ExtensionKit/Extensions",
        isDirectory: true
    )
    public static let preferencePanesDirectory = URL(
        fileURLWithPath: "/System/Library/PreferencePanes",
        isDirectory: true
    )

    /// Read once. The set of panes changes when macOS is updated, which is not something to poll
    /// for (§65) — and the process does not outlive an update.
    public static let shared: [SettingsPane] = panes()

    public static func panes(
        in directory: URL = extensionsDirectory,
        legacyPanes: URL = preferencePanesDirectory
    ) -> [SettingsPane] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var seen = Set<String>()
        var panes: [SettingsPane] = []
        for bundle in contents where bundle.pathExtension == "appex" {
            guard let pane = pane(at: bundle, legacyPanes: legacyPanes),
                  seen.insert(pane.id).inserted
            else { continue }
            panes.append(pane)
        }
        return panes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func pane(at bundleURL: URL, legacyPanes: URL = preferencePanesDirectory) -> SettingsPane? {
        guard let info = NSDictionary(contentsOf: bundleURL.appendingPathComponent("Contents/Info.plist")),
              let attributes = (info["EXAppExtensionAttributes"] as? [String: Any])?["SettingsExtensionAttributes"]
                  as? [String: Any],
              // Only the extensions that say they take the URL scheme; the rest cannot be opened
              // this way and a result that does nothing is worse than no result.
              attributes["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true,
              let identifier = first(attributes["legacyBundleIdentifier"])
        else { return nil }

        let legacyName = first(attributes["legacyPrefPaneBundleName"]).flatMap { pane -> String? in
            let plist = legacyPanes.appendingPathComponent(pane).appendingPathComponent("Contents/Info.plist")
            return (NSDictionary(contentsOf: plist)?["CFBundleName"]) as? String
        }
        let bundleName = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
        guard let name = displayName(bundleName: bundleName, legacyName: legacyName) else { return nil }
        return SettingsPane(id: identifier, name: name)
    }

    /// Some of these keys hold an array — Printers & Scanners and the battery pane each answer to
    /// two legacy identifiers. The first is the one System Settings itself opens.
    static func first(_ value: Any?) -> String? {
        if let string = value as? String { return string.isEmpty ? nil : string }
        if let list = value as? [String] { return list.first(where: { !$0.isEmpty }) }
        return nil
    }

    /// What to call a pane.
    ///
    /// The extension's own display name is usually right — "Displays", "Keyboard", "Screen Time" —
    /// and occasionally it is the developer's bundle name: "AccessibilitySettingsExtension",
    /// "MouseExtension". The legacy pane's `CFBundleName` is the better answer when there is one,
    /// because that is the string the old System Preferences drew, so it wins; the extension name
    /// is the fallback, tidied.
    static func displayName(bundleName: String?, legacyName: String?) -> String? {
        if let legacyName, !legacyName.isEmpty { return legacyName }
        guard let bundleName, !bundleName.isEmpty else { return nil }
        var name = bundleName
        for suffix in ["Settings Extension", "SettingsExtension", "PreferenceExtension",
                       "PreferencesExtension", "Preference Extension", "Extension", "Ext"] {
            if name.hasSuffix(suffix), name.count > suffix.count {
                name = String(name.dropLast(suffix.count))
                break
            }
        }
        name = splitCamelCase(name.trimmingCharacters(in: .whitespaces))
        return name.isEmpty ? nil : name
    }

    /// `DateAndTime` is a bundle name, not a title. Splitting on the case change gives back the
    /// words; a name that is already spaced comes through untouched.
    static func splitCamelCase(_ name: String) -> String {
        guard !name.contains(" ") else { return name }
        var out = ""
        var previous: Character?
        for character in name {
            if character.isUppercase, let previous, !previous.isUppercase { out.append(" ") }
            out.append(character)
            previous = character
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
