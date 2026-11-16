import AppKit
import Foundation

/// One thing inside a pinned folder (M21).
public struct FolderItem: Sendable, Equatable, Identifiable {
    public var url: URL
    public var name: String
    public var isDirectory: Bool
    /// When it arrived in the folder, else when it was created; `nil` if the file system says neither.
    public var dateAdded: Date?

    public var id: String { url.path }

    public init(url: URL, name: String, isDirectory: Bool, dateAdded: Date? = nil) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.dateAdded = dateAdded
    }
}

/// How a stack orders what it lists.
public enum FolderSort: String, Codable, Sendable, CaseIterable {
    case name, dateAdded
}

extension FolderSort {
    /// Downloads is useful because the newest file is on top; everything else reads by name.
    public static func defaultSort(
        forPath path: String,
        downloads: String = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
    ) -> FolderSort {
        !downloads.isEmpty && path == downloads ? .dateAdded : .name
    }
}

/// What a stack found when it looked. The three cases are different answers and the popover says
/// which: an empty folder is not a folder macOS would not let us read, and neither is one that has
/// been moved since it was pinned (M21).
public enum FolderListing: Sendable, Equatable {
    case items([FolderItem])
    case refused
    case missing

    public var items: [FolderItem] {
        guard case .items(let items) = self else { return [] }
        return items
    }
}

/// Lists a pinned folder. Read when the stack opens, never watched: a folder that changes while its
/// popover is open is rarer than an `FSEvents` stream per pinned folder is expensive.
public enum FolderStackService {
    /// A stack is a glance, not a file manager. The listing stops here, and the header counts
    /// what is listed — a folder with more shows this many, with no sign that there are others.
    public static let limit = 60

    public static func list(_ url: URL, limit: Int = limit, sort: FolderSort = .name) -> FolderListing {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return .missing }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Self.keys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            // Desktop, Documents and Downloads are TCC-protected: a refusal arrives as an error,
            // and reporting it as an empty folder would be a lie the user cannot act on.
            Log.system.notice("Cannot read pinned folder: \(error.localizedDescription, privacy: .public)")
            return .refused
        }

        let items = contents.map { item -> FolderItem in
            let values = try? item.resourceValues(forKeys: Set(Self.keys))
            // An application is one item, not a directory to walk into — and neither is any other
            // package.
            let isDirectory = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
            return FolderItem(
                url: item,
                name: values?.localizedName ?? item.lastPathComponent,
                isDirectory: isDirectory,
                dateAdded: values?.addedToDirectoryDate ?? values?.creationDate
            )
        }
        // Sorted before the limit: the newest 60 are not the first 60 by name.
        return .items(Array(sorted(items, by: sort).prefix(limit)))
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .localizedNameKey, .addedToDirectoryDateKey, .creationDateKey,
    ]

    /// By name: folders first, then files, each alphabetical the way Finder sorts them. By date:
    /// newest first, folders mixed in, undated last, ties by name.
    static func sorted(_ items: [FolderItem], by sort: FolderSort = .name) -> [FolderItem] {
        switch sort {
        case .name:
            return items.sorted { left, right in
                if left.isDirectory != right.isDirectory { return left.isDirectory }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
        case .dateAdded:
            return items.sorted { left, right in
                switch (left.dateAdded, right.dateAdded) {
                case let (a?, b?) where a != b: return a > b
                case (nil, .some): return false
                case (.some, nil): return true
                default: return left.name.localizedStandardCompare(right.name) == .orderedAscending
                }
            }
        }
    }

    /// The name a pinned folder draws: the volume's or folder's own display name, not its path.
    public static func displayName(of url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
    }
}
