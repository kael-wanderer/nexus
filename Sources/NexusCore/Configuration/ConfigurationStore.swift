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

    /// No breaking schema change has occurred yet, so this list is empty. `NexusConfiguration`
    /// decodes every field with a default, so purely additive changes need no migration.
    public static let standardMigrations: [any ConfigurationMigration] = []

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
