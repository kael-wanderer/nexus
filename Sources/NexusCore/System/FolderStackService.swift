import AppKit
import Foundation

/// One thing inside a pinned folder (M21).
public struct FolderItem: Sendable, Equatable, Identifiable {
    public var url: URL
    public var name: String
    public var isDirectory: Bool

    public var id: String { url.path }

    public init(url: URL, name: String, isDirectory: Bool) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
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
    /// A stack is a glance, not a file manager. The header says the real count, so a capped listing
    /// is visible rather than silent.
    public static let limit = 60

    public static func list(_ url: URL, limit: Int = limit) -> FolderListing {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return .missing }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .localizedNameKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            // Desktop, Documents and Downloads are TCC-protected: a refusal arrives as an error,
            // and reporting it as an empty folder would be a lie the user cannot act on.
            Log.system.notice("Cannot read pinned folder: \(error.localizedDescription, privacy: .public)")
            return .refused
        }

        let items = contents.map { item -> FolderItem in
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .localizedNameKey])
            // An application is one item, not a directory to walk into — and neither is any other
            // package.
            let isDirectory = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
            return FolderItem(
                url: item,
                name: values?.localizedName ?? item.lastPathComponent,
                isDirectory: isDirectory
            )
        }
        return .items(Array(sorted(items).prefix(limit)))
    }

    /// Folders first, then files, each alphabetical the way Finder sorts them. Sorting by date is
    /// the Dock's other option and one comparator away, when somebody asks for it.
    static func sorted(_ items: [FolderItem]) -> [FolderItem] {
        items.sorted { left, right in
            if left.isDirectory != right.isDirectory { return left.isDirectory }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    /// The name a pinned folder draws: the volume's or folder's own display name, not its path.
    public static func displayName(of url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
    }
}
