import Foundation

/// A colour a group may be tinted with (D108). Stored by name rather than as a hex string: the
/// name survives a change of palette, reads in `defaults read`, and lets the system pick the shade
/// that suits dark mode and Increase Contrast.
public enum GroupTint: String, Codable, Sendable, CaseIterable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
}

/// A folder in the dock: a handful of applications behind one row (M13).
public struct ApplicationGroup: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Auto-named from the members' `LSApplicationCategoryType`, renameable.
    public var name: String
    public var applications: [String]
    /// Optional decoration, both `nil` until somebody picks one (D108).
    public var tint: GroupTint?
    /// One character, so it fits the corner of a 2×2 tile at any icon size.
    public var emoji: String?

    public init(
        id: UUID = UUID(),
        name: String,
        applications: [String],
        tint: GroupTint? = nil,
        emoji: String? = nil
    ) {
        self.id = id
        self.name = name
        self.applications = applications
        self.tint = tint
        self.emoji = Self.trimmedEmoji(emoji)
    }

    /// Tolerant decode, like every other stored type: a group written by a later version, or by
    /// hand, must not take the whole dock down with it. A group written by an *earlier* version has
    /// no tint and no emoji, which is exactly what `decodeIfPresent` gives it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        applications = try container.decodeIfPresent([String].self, forKey: .applications) ?? []
        tint = try container.decodeIfPresent(GroupTint.self, forKey: .tint)
        emoji = Self.trimmedEmoji(try container.decodeIfPresent(String.self, forKey: .emoji))
    }

    /// The first character of whatever was typed, or nothing. A field somebody has pasted a
    /// sentence into must not become a tile nobody can read.
    public static func trimmedEmoji(_ value: String?) -> String? {
        guard let first = value?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first)
    }
}

/// One slot in the dock: an application, a group of them, or a folder (M21).
///
/// Stored as `{"application": "com.apple.Safari"}` / `{"group": {…}}` / `{"folder": "/path"}`
/// rather than as an enum with an associated value in Swift's default shape, so the JSON is
/// legible in `defaults read`.
public enum DockEntry: Codable, Sendable, Equatable, Identifiable {
    case application(String)
    case group(ApplicationGroup)
    /// A path, not a security-scoped bookmark: Nexus is not sandboxed, so a bookmark would buy
    /// nothing but a resolve step (M21).
    case folder(String)

    /// Stable across a rename and a reorder, and distinct from any bundle identifier.
    public var id: String {
        switch self {
        case .application(let identifier): identifier
        case .group(let group): Self.identifierPrefix + group.id.uuidString
        case .folder(let path): Self.folderPrefix + path
        }
    }

    public static let identifierPrefix = "group:"
    public static let folderPrefix = "folder:"

    /// Every application in this slot, in order — one for an application, all members for a group.
    public var applications: [String] {
        switch self {
        case .application(let identifier): [identifier]
        case .group(let group): group.applications
        case .folder: []
        }
    }

    public var group: ApplicationGroup? {
        guard case .group(let group) = self else { return nil }
        return group
    }

    public var folderPath: String? {
        guard case .folder(let path) = self else { return nil }
        return path
    }

    public var applicationIdentifier: String? {
        guard case .application(let identifier) = self else { return nil }
        return identifier
    }

    private enum CodingKeys: String, CodingKey {
        case application
        case group
        case folder
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
        if let path = try container.decodeIfPresent(String.self, forKey: .folder) {
            self = .folder(path)
            return
        }
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: container.codingPath,
                debugDescription: "Not an application, a group or a folder"
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .application(let identifier):
            try container.encode(identifier, forKey: .application)
        case .group(let group):
            try container.encode(group, forKey: .group)
        case .folder(let path):
            try container.encode(path, forKey: .folder)
        }
    }
}

extension [DockEntry] {
    /// Repairs what a stored dock can get wrong, on load and after every edit:
    ///
    /// - a group over capacity keeps its first `capacity` members,
    /// - a duplicate application keeps its first slot,
    /// - a group of one becomes that application, and a group of none disappears — a group with
    ///   one thing in it is a lie, and an empty one is a dead row,
    /// - the same folder pinned twice keeps its first slot, and a folder with no path is dropped.
    public func repaired(capacity: Int) -> [DockEntry] {
        var seen = Set<String>()
        var result: [DockEntry] = []
        for entry in self {
            switch entry {
            case .application(let identifier):
                guard !identifier.isEmpty, seen.insert(identifier).inserted else { continue }
                result.append(entry)
            case .folder(let path):
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(DockEntry.folderPrefix + trimmed).inserted
                else { continue }
                result.append(.folder(trimmed))
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
