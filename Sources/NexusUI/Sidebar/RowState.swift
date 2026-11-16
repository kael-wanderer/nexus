import CoreGraphics
import NexusCore

/// Everything a row's body depends on besides its own item. Equatable, so a row whose state
/// did not change is not redrawn.
public struct RowState: Equatable, Sendable {
    public var iconSize: CGFloat
    public var rowHeight: CGFloat
    public var position: SidebarPosition
    public var expanded: Bool
    /// `behavior.showWindowCount && windowCountsAreExact`.
    public var showsWindowCount: Bool
    public var badge: String?
    public var isLaunching: Bool
    public var isFocused: Bool
    public var isGroupCandidate: Bool
    /// Always false until a file drop sets it.
    public var isFileDropTarget: Bool
    public var isDragging: Bool
    public var isEditing: Bool
    /// `false` before the row, `true` after it, `nil` when the caret is not on this row.
    public var dropEdge: Bool?
    /// `behavior.groupColorsAndEmoji`: only a group row reads it.
    public var showsGroupStyle: Bool
    public var isVertical: Bool { position.isVertical }
}

extension SidebarViewModel {
    public func rowState(for id: String) -> RowState {
        RowState(
            iconSize: appearance.iconSize,
            rowHeight: SidebarLayout.rowHeight(appearance),
            position: appearance.position,
            expanded: isExpanded,
            showsWindowCount: behavior.showWindowCount && windowCountsAreExact,
            badge: badge(for: id),
            isLaunching: isLaunching(id),
            isFocused: focusedRowID == id,
            isGroupCandidate: groupCandidate == id,
            isFileDropTarget: false,
            isDragging: draggingIdentifier == id,
            isEditing: isEditing,
            dropEdge: dropEdge(for: id),
            showsGroupStyle: behavior.groupColorsAndEmoji
        )
    }

    /// A group wears the first badge any of its members has.
    func rowState(forGroup group: SidebarGroup) -> RowState {
        var state = rowState(for: group.id)
        state.badge = badge(forGroup: group)
        return state
    }
}
