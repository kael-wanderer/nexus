import Foundation

public protocol ConfigurationStoring: Sendable {
    func load() -> NexusConfiguration
    func save(_ configuration: NexusConfiguration) throws
}

/// A migration step transforms the raw JSON dictionary of `fromVersion` into `fromVersion + 1`.
/// Operating on the dictionary rather than on typed structs means obsolete versions of
/// `NexusConfiguration` never have to be kept in the source tree (D9).
public protocol ConfigurationMigration: Sendable {
    var fromVersion: Int { get }
    func migrate(_ json: inout [String: Any]) throws
}

public enum ConfigurationLoadOutcome: Equatable, Sendable {
    case defaultsNoStoredData
    case decoded
    case migrated(from: Int)
    case newerVersionIgnored(Int)
    case corruptQuarantined(String)
}

/// Versioned JSON in `UserDefaults` (D9). Never crashes on bad data, never destroys it (D10).
public final class ConfigurationStore: ConfigurationStoring {
    public static let defaultKey = "configuration"

    // UserDefaults is documented as thread-safe but is not annotated `Sendable`.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key: String
    private let migrations: [any ConfigurationMigration]
    private let lock = NSLock()
    nonisolated(unsafe) private var lastOutcome: ConfigurationLoadOutcome = .defaultsNoStoredData

    public init(
        defaults: UserDefaults = .standard,
        key: String = ConfigurationStore.defaultKey,
        migrations: [any ConfigurationMigration] = ConfigurationStore.standardMigrations
    ) {
        self.defaults = defaults
        self.key = key
        self.migrations = migrations.sorted { $0.fromVersion < $1.fromVersion }
    }

    /// Purely additive changes need no migration — every field decodes with a default. Only a
    /// change in the *shape* of stored data lands here.
    public static let standardMigrations: [any ConfigurationMigration] = [
        PinnedEntriesMigration(),
        AutomaticRowLimitsMigration(),
    ]

    public var outcomeOfLastLoad: ConfigurationLoadOutcome {
        lock.lock()
        defer { lock.unlock() }
        return lastOutcome
    }

    public func load() -> NexusConfiguration {
        guard let data = defaults.data(forKey: key) else {
            record(.defaultsNoStoredData)
            Log.app.notice("No stored configuration; using defaults")
            return NexusConfiguration()
        }
        do {
            return try loadThrowing(data)
        } catch {
            let suffix = ISO8601DateFormatter().string(from: Date())
            let quarantineKey = "\(key).corrupt.\(suffix)"
            defaults.set(data, forKey: quarantineKey)
            record(.corruptQuarantined(quarantineKey))
            Log.app.error("Configuration unreadable, copied aside to \(quarantineKey, privacy: .public); using defaults")
            return NexusConfiguration()
        }
    }

    private func loadThrowing(_ data: Data) throws -> NexusConfiguration {
        struct VersionProbe: Decodable { let version: Int }
        let decoder = JSONDecoder()
        let storedVersion = try decoder.decode(VersionProbe.self, from: data).version

        if storedVersion > NexusConfiguration.currentVersion {
            // A newer Nexus wrote this. Run defaults in memory; leave the bytes untouched (D10).
            record(.newerVersionIgnored(storedVersion))
            Log.app.warning(
                "Stored configuration version \(storedVersion, privacy: .public) is newer than \(NexusConfiguration.currentVersion, privacy: .public); using defaults without overwriting"
            )
            return NexusConfiguration()
        }

        var payload = data
        if storedVersion < NexusConfiguration.currentVersion {
            payload = try applyMigrations(to: data, from: storedVersion)
            record(.migrated(from: storedVersion))
        } else {
            record(.decoded)
        }
        return try decoder.decode(NexusConfiguration.self, from: payload)
    }

    private func applyMigrations(to data: Data, from storedVersion: Int) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NexusError.notFound
        }
        var version = storedVersion
        while version < NexusConfiguration.currentVersion {
            guard let step = migrations.first(where: { $0.fromVersion == version }) else {
                Log.app.error("No migration from configuration version \(version, privacy: .public)")
                throw NexusError.notFound
            }
            try step.migrate(&json)
            version += 1
            json["version"] = version
        }
        return try JSONSerialization.data(withJSONObject: json)
    }

    public func save(_ configuration: NexusConfiguration) throws {
        var stored = configuration
        stored.version = NexusConfiguration.currentVersion
        stored.appearance.clamp()
        let data = try JSONEncoder().encode(stored)
        defaults.set(data, forKey: key)
    }

    private func record(_ outcome: ConfigurationLoadOutcome) {
        lock.lock()
        lastOutcome = outcome
        lock.unlock()
    }
}

/// Version 1 → 2 (M13): the dock stops being a list of bundle identifiers and becomes a list of
/// entries, because a group is not an application.
///
/// The old `pinnedApplications` key is left in place rather than removed. Nothing reads it, and
/// `NexusConfiguration.encode` keeps writing it, so downgrading to a build that only knows v1
/// finds its dock instead of an empty bar.
public struct PinnedEntriesMigration: ConfigurationMigration {
    public let fromVersion = 1

    public init() {}

    public func migrate(_ json: inout [String: Any]) throws {
        guard json["pinnedEntries"] == nil else { return }
        let pinned = json["pinnedApplications"] as? [String] ?? []
        json["pinnedEntries"] = pinned.map { ["application": $0] }
    }
}

/// Version 2 → 3 (M14): the row limits stop being the number of rows the bar shows and become a
/// ceiling on it, with zero meaning "as many as the screen holds".
///
/// The values written by the version that shipped them are dropped rather than kept: they were
/// defaults nobody chose (10 and 5), and keeping them would cap a bar with half the screen free —
/// which is the bug this change exists to fix. A deliberate ceiling set after this point survives,
/// because it is stored against the new meaning.
public struct AutomaticRowLimitsMigration: ConfigurationMigration {
    public let fromVersion = 2

    public init() {}

    public func migrate(_ json: inout [String: Any]) throws {
        var appearance = json["appearance"] as? [String: Any] ?? [:]
        appearance["pinnedLimit"] = 0
        appearance["runningLimit"] = 0
        json["appearance"] = appearance
    }
}

/// In-memory store for tests and previews.
public final class InMemoryConfigurationStore: ConfigurationStoring {
    private let lock = NSLock()
    nonisolated(unsafe) private var configuration: NexusConfiguration

    public init(_ configuration: NexusConfiguration = NexusConfiguration()) {
        self.configuration = configuration
    }

    public func load() -> NexusConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return configuration
    }

    public func save(_ configuration: NexusConfiguration) throws {
        lock.lock()
        self.configuration = configuration
        lock.unlock()
    }
}
