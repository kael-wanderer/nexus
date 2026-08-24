import Foundation
import NexusCore

/// One block of the grid. Flat grouping produces exactly one of these with an empty title, which
/// is what keeps the view free of a special case for "not grouped" (M25).
public struct SwitcherSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let windows: [NexusWindow]

    public init(id: String, title: String, windows: [NexusWindow]) {
        self.id = id
        self.title = title
        self.windows = windows
    }
}
