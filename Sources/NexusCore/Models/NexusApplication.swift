import CoreGraphics
import Foundation

public struct NexusApplication: Identifiable, Sendable, Equatable {
    public let identity: ApplicationIdentity
    public let name: String
    public let bundleURL: URL
    public var isRunning: Bool
    public var isActive: Bool
    public var windowCount: Int

    public var id: String { identity.bundleIdentifier }

    public init(
        identity: ApplicationIdentity,
        name: String,
        bundleURL: URL,
        isRunning: Bool = false,
        isActive: Bool = false,
        windowCount: Int = 0
    ) {
        self.identity = identity
        self.name = name
        self.bundleURL = bundleURL
        self.isRunning = isRunning
        self.isActive = isActive
        self.windowCount = windowCount
    }
}

public struct NexusWindow: Identifiable, Sendable, Equatable {
    public let identity: WindowIdentity
    public var title: String
    public var isMinimized: Bool
    public var frame: CGRect
    public var displayID: DisplayIdentity?
    /// Owning application's display name, carried so search results can say "VS Code — Bugler".
    public var applicationName: String

    public var id: String { "\(identity.owner.bundleIdentifier)#\(identity.number)" }

    /// What the window list, the flyout's cards and its chips all show — a window with no title
    /// still needs a row to click, and blank is not a label.
    public var displayTitle: String {
        title.isEmpty ? String(localized: "Untitled window") : title
    }

    public init(
        identity: WindowIdentity,
        title: String,
        isMinimized: Bool = false,
        frame: CGRect = .zero,
        displayID: DisplayIdentity? = nil,
        applicationName: String = ""
    ) {
        self.identity = identity
        self.title = title
        self.isMinimized = isMinimized
        self.frame = frame
        self.displayID = displayID
        self.applicationName = applicationName
    }
}
