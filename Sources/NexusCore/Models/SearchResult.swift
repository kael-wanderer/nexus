import Foundation

public enum SearchProviderID: String, Sendable, Hashable, CaseIterable {
    case application
    case window
    case file
    case action
}

public enum SearchCategory: String, Sendable, Hashable, CaseIterable {
    case application
    case window
    case file
    case action

    public var title: String {
        switch self {
        case .application: String(localized: "Applications")
        case .window: String(localized: "Windows")
        case .file: String(localized: "Files")
        case .action: String(localized: "Actions")
        }
    }

    /// Order in which categories appear in the palette. Files rank last: the largest and least
    /// intentional result set.
    public var order: Int {
        switch self {
        case .application: 0
        case .window: 1
        case .action: 2
        case .file: 3
        }
    }

    public var resultCap: Int {
        switch self {
        case .application: 8
        case .window: 8
        case .file: 6
        case .action: 5
        }
    }
}

public enum ResultIcon: Sendable, Hashable {
    case application(URL)
    case file(URL)
    case symbol(String)
}

/// Built-in actions (§13). No shell, no AppleScript, no Automation permission (D15).
public enum BuiltInAction: String, Sendable, Hashable, CaseIterable {
    case openTerminal
    case openDownloads
    case openDocuments
    case openHome
    case openSystemSettings
    case lockScreen

    public var title: String {
        switch self {
        case .openTerminal: String(localized: "Open Terminal")
        case .openDownloads: String(localized: "Open Downloads")
        case .openDocuments: String(localized: "Open Documents")
        case .openHome: String(localized: "Open Home")
        case .openSystemSettings: String(localized: "Open System Settings")
        case .lockScreen: String(localized: "Lock Screen")
        }
    }

    public var symbol: String {
        switch self {
        case .openTerminal: "terminal"
        case .openDownloads: "arrow.down.circle"
        case .openDocuments: "doc"
        case .openHome: "house"
        case .openSystemSettings: "gearshape"
        case .lockScreen: "lock"
        }
    }
}

/// Results carry a value, not a closure (D6): `Sendable`, comparable, and testable without
/// executing anything. One `ActionRunner` in the app layer performs the side effects.
public enum NexusActionDescriptor: Sendable, Hashable {
    case launchApplication(String)
    case activateWindow(WindowIdentity)
    case openFile(URL)
    case openURL(URL)
    case quitApplication(String)
    case runBuiltInAction(BuiltInAction)
}

public struct SearchResult: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let icon: ResultIcon
    public let category: SearchCategory
    public var score: Double
    public let action: NexusActionDescriptor
    /// Set by providers that know it; feeds the running-application state boost.
    public var isRunning: Bool
    /// Secondary action for ⇧⏎ — reveal in Finder, or nil when there is none.
    public let secondaryAction: NexusActionDescriptor?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: ResultIcon,
        category: SearchCategory,
        score: Double = 0,
        action: NexusActionDescriptor,
        isRunning: Bool = false,
        secondaryAction: NexusActionDescriptor? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.category = category
        self.score = score
        self.action = action
        self.isRunning = isRunning
        self.secondaryAction = secondaryAction
    }
}

public struct SearchQuery: Sendable, Equatable {
    public let text: String
    /// Monotonic; snapshots carrying a stale token are dropped at the view-model boundary.
    public let token: UInt64

    public init(text: String, token: UInt64) {
        self.text = text
        self.token = token
    }

    public var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isEmpty: Bool { trimmed.isEmpty }
}

public struct SearchSnapshot: Sendable, Equatable {
    public let token: UInt64
    public let results: [SearchResult]
    public let isComplete: Bool

    public init(token: UInt64, results: [SearchResult], isComplete: Bool) {
        self.token = token
        self.results = results
        self.isComplete = isComplete
    }
}
