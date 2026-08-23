import Foundation

/// A folder in the dock: a handful of applications behind one row (M13).
public struct ApplicationGroup: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Auto-named from the members' `LSApplicationCategoryType`, renameable.
    public var name: String
    public var applications: [String]

    public init(id: UUID = UUID(), name: String, applications: [String]) {
        self.id = id
        self.name = name
        self.applications = applications
    }

    /// Tolerant decode, like every other stored type: a group written by a later version, or by
    /// hand, must not take the whole dock down with it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        applications = try container.decodeIfPresent([String].self, forKey: .applications) ?? []
    }
}

/// One slot in the dock: an application, or a group of them.
///
/// Stored as `{"application": "com.apple.Safari"}` / `{"group": {…}}` rather than as an enum with
/// an associated value in Swift's default shape, so the JSON is legible in `defaults read`.
public enum DockEntry: Codable, Sendable, Equatable, Identifiable {
    case application(String)
    case group(ApplicationGroup)

    /// Stable across a rename and a reorder, and distinct from any bundle identifier.
    public var id: String {
        switch self {
        case .application(let identifier): identifier
        case .group(let group): Self.identifierPrefix + group.id.uuidString
        }
    }

    public static let identifierPrefix = "group:"

    /// Every application in this slot, in order — one for an application, all members for a group.
    public var applications: [String] {
        switch self {
        case .application(let identifier): [identifier]
        case .group(let group): group.applications
        }
    }

    public var group: ApplicationGroup? {
        guard case .group(let group) = self else { return nil }
        return group
    }

    public var applicationIdentifier: String? {
        guard case .application(let identifier) = self else { return nil }
        return identifier
    }

    private enum CodingKeys: String, CodingKey {
        case application
        case group
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let identifier = try container.decodeIfPresent(String.self, forKey: .application) {
            self = .application(identifier)
            return
        }
        if let group = try container.decodeIfPresent(ApplicationGroup.self, forKey: .group) {
            self = .group(group)
            return
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: container.codingPath, debugDescription: "Neither an application nor a group")
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .application(let identifier):
            try container.encode(identifier, forKey: .application)
        case .group(let group):
            try container.encode(group, forKey: .group)
        }
    }
}

extension [DockEntry] {
    /// Repairs what a stored dock can get wrong, on load and after every edit:
    ///
    /// - a group over capacity keeps its first `capacity` members,
    /// - a duplicate application keeps its first slot,
    /// - a group of one becomes that application, and a group of none disappears — a folder with
    ///   one thing in it is a lie, and an empty one is a dead row.
    public func repaired(capacity: Int) -> [DockEntry] {
        var seen = Set<String>()
        var result: [DockEntry] = []
        for entry in self {
            switch entry {
            case .application(let identifier):
                guard !identifier.isEmpty, seen.insert(identifier).inserted else { continue }
                result.append(entry)
            case .group(var group):
                group.applications = group.applications.filter {
                    !$0.isEmpty && seen.insert($0).inserted
                }
                group.applications = [String](group.applications.prefix(capacity))
                switch group.applications.count {
                case 0: continue
                case 1: result.append(.application(group.applications[0]))
                default: result.append(.group(group))
                }
            }
        }
        return result
    }

    /// Index of the slot holding `identifier`, whether directly or inside a group.
    public func index(containing identifier: String) -> Int? {
        firstIndex { $0.applications.contains(identifier) }
    }
}
