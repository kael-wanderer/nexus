import Foundation

/// What a search is allowed to look at (M19).
///
/// A scope is not the provider toggles in Settings: those switch a provider off for every search,
/// for ever. This one is for the search being typed, and the palette opens on `.everything` again
/// next time.
public enum SearchScope: String, Sendable, Hashable, Codable, CaseIterable {
    case everything
    case applications
    case filesAndFolders
    case files
    case folders
    case settings

    public var title: String {
        switch self {
        case .everything: String(localized: "Everything")
        case .applications: String(localized: "Applications")
        case .filesAndFolders: String(localized: "Files & Folders")
        case .files: String(localized: "Files")
        case .folders: String(localized: "Folders")
        case .settings: String(localized: "Settings & Actions")
        }
    }

    public var symbol: String {
        switch self {
        case .everything: "magnifyingglass"
        case .applications: "app"
        case .filesAndFolders: "folder.badge.plus"
        case .files: "doc"
        case .folders: "folder"
        case .settings: "gearshape"
        }
    }

    /// The providers this scope lets run. Windows are only reachable from `.everything`: a window
    /// is not a kind of thing anybody goes looking for by category, it is the application you
    /// already named.
    ///
    /// `.settings` is the action provider, which is where both halves of "things you do rather
    /// than open" live: the built-in actions, and the panes of System Settings.
    public var providers: Set<SearchProviderID> {
        switch self {
        case .everything: Set(SearchProviderID.allCases)
        case .applications: [.application]
        case .filesAndFolders, .files, .folders: [.file]
        case .settings: [.action]
        }
    }

    /// Files versus folders is one clause on the Spotlight query the file provider already runs,
    /// not a second search and not a filter over the results.
    public var fileKind: FileKind {
        switch self {
        case .files: .filesOnly
        case .folders: .foldersOnly
        default: .any
        }
    }

    /// `⌃1`…`⌃6`. Not `⌘1`…`⌘6`: those already run the numbered result, and a shortcut that
    /// silently means two things is worse than a less obvious one.
    public var shortcut: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    public static func scope(forShortcut number: Int) -> SearchScope? {
        guard allCases.indices.contains(number - 1) else { return nil }
        return allCases[number - 1]
    }

    /// Wraps, in the declared order, so `⇥` walks the whole list without a dead end.
    public func cycled(by delta: Int) -> SearchScope {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        let next = (index + delta) % all.count
        return all[next < 0 ? next + all.count : next]
    }
}
