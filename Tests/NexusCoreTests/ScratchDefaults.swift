import Foundation

/// A `UserDefaults` that never reaches the disk.
///
/// A real suite is a property list in `~/Library/Preferences`, and the preferences daemon keeps
/// one — empty, but there — even after the domain is cleared. Every test that made a suite left
/// a file behind on every run. `ConfigurationStore` only reads and writes values by key, so the
/// tests get a dictionary behind the same interface instead.
final class ScratchDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    init() {
        // The designated initialiser needs a suite; `nil` is the standard one. Nothing is ever
        // read from or written to it, because every accessor the store uses is overridden below.
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock { values[defaultName] }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { values[defaultName] = value }
    }

    override func removeObject(forKey defaultName: String) {
        lock.withLock { values[defaultName] = nil }
    }

    override func data(forKey defaultName: String) -> Data? {
        object(forKey: defaultName) as? Data
    }

    override func string(forKey defaultName: String) -> String? {
        object(forKey: defaultName) as? String
    }
}

func makeDefaults() -> UserDefaults {
    ScratchDefaults()
}
