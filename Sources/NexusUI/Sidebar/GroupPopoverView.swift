import AppKit
import NexusCore
import SwiftUI

/// What a group looks like when opened: its applications on a grid, beside the bar (M13).
///
/// The panel takes the keyboard while, and only while, the title is being edited (D104) — the same
/// bargain the bar's keyboard mode makes: the user asked for it, by clicking the name.
@MainActor
@Observable
public final class GroupPopoverViewModel {
    public private(set) var group: SidebarGroup?

    /// Whether the title is being edited, and what has been typed into it so far.
    public private(set) var isRenaming = false
    public var draftName = ""
    /// The emoji field's contents while the title is being edited (D108).
    public var draftEmoji = ""
    /// Whether colours and emoji are switched on at all. Set by the composition root from the
    /// preference, so the editor is absent rather than inert when they are off.
    public var showsStyleEditor = true

    /// Icons on a grid, or a list. Pushed from `behavior.groupLayout` by the composition root, the
    /// same way the style editor's switch is (D108).
    public var layout: GroupLayout = .icons

    /// Set by the composition root, so a click here does the same thing a click in the bar does.
    @ObservationIgnored public var launch: ((SidebarItem) -> Void)?
    @ObservationIgnored public var remove: ((SidebarItem) -> Void)?
    /// Commits a new name. Injected, because the dock belongs to the bar's model, not to this one.
    @ObservationIgnored public var rename: ((SidebarGroup, String) -> Void)?
    /// Commits a colour and an emoji (D108).
    @ObservationIgnored public var restyle: ((SidebarGroup, GroupTint?, String?) -> Void)?
    /// A row from the bar was dropped on one of the members, which is where it goes (P2).
    @ObservationIgnored public var dropOnMember: ((String, SidebarItem) -> Void)?
    /// Asks the panel for the keyboard, and gives it back. Set by `PanelController` (D104).
    @ObservationIgnored public var setEditing: ((Bool) -> Void)?
    @ObservationIgnored public var onDismiss: (() -> Void)?

    public init() {}

    public func show(_ group: SidebarGroup) {
        self.group = group
    }

    // MARK: - Renaming

    /// The title was clicked. The field appears with the name in it, selected.
    public func beginRename() {
        guard let group, !isRenaming else { return }
        draftName = group.name
        draftEmoji = group.group.emoji ?? ""
        isRenaming = true
        setEditing?(true)
    }

    /// Return, or anything that takes the popover away while the field is open: a name typed and
    /// left alone is a name the user meant.
    public func commitRename() {
        guard isRenaming, let group else { return }
        isRenaming = false
        setEditing?(false)
        rename?(group, draftName)
        guard draftEmoji != (group.group.emoji ?? "") else { return }
        restyle?(group, group.group.tint, draftEmoji)
    }

    /// A swatch was clicked. Applied at once rather than on commit: a colour is its own preview, and
    /// waiting for Return to see it is the wrong way round.
    public func setTint(_ tint: GroupTint?) {
        guard let group else { return }
        restyle?(group, tint, draftEmoji.isEmpty ? group.group.emoji : draftEmoji)
    }

    /// Escape: the name goes back to what it was.
    public func cancelRename() {
        guard isRenaming else { return }
        isRenaming = false
        setEditing?(false)
    }

    /// Called after every dock edit: the popover has to follow its group, or close if the group
    /// stopped existing (ungrouped, emptied, dissolved down to one application).
    public func update(from rows: [SidebarRow]) {
        guard let current = group else { return }
        guard let match = rows.compactMap(\.group).first(where: { $0.id == current.id }) else {
            hide()
            return
        }
        group = match
    }

    public func hide() {
        guard group != nil else { return }
        commitRename()
        group = nil
        onDismiss?()
    }

    /// Columns for the grid: 3 for a group of up to 9, 4 beyond that. Same shape as the capacity.
    public var columns: Int {
        (group?.items.count ?? 0) > 9 ? 4 : 3
    }

    /// How wide the panel draws. The grid is as wide as its columns; the list is one width for
    /// every group, so opening two groups in a row does not make the panel jump about.
    public var panelWidth: CGFloat {
        switch layout {
        case .icons:
            return CGFloat(columns) * (GroupPopoverView.tileSize + 4) + GroupPopoverView.padding * 2
        case .list:
            return GroupPopoverView.listWidth
        }
    }
}

public struct GroupPopoverView: View {
    @Bindable var model: GroupPopoverViewModel

    public static let tileSize: CGFloat = 76
    public static let padding: CGFloat = 10
    public static let listWidth: CGFloat = 240
    public static let listRowHeight: CGFloat = 28

    public init(model: GroupPopoverViewModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if let group = model.group {
                content(group)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.group?.name ?? String(localized: "Group"))
    }

    private func content(_ group: SidebarGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(group)
            if model.layout == .icons {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(Self.tileSize), spacing: 4),
                        count: model.columns
                    ),
                    spacing: 4
                ) {
                    members(group)
                }
            } else {
                VStack(spacing: 0) {
                    members(group)
                }
            }
            if model.isRenaming, model.showsStyleEditor { styleEditor(group) }
        }
        .padding(Self.padding)
        .frame(width: model.panelWidth)
    }

    /// One tile or one row per application — the same clicks, menu, drag and remove badge either
    /// way; only the shape of the label changes.
    private func members(_ group: SidebarGroup) -> some View {
        ForEach(group.items) { item in
            GroupMemberTile(
                item: item,
                layout: model.layout,
                launch: { model.launch?(item) },
                remove: { model.remove?(item) },
                // A drag that sprang this popover open can be let go on a tile, and the
                // application lands in the group *there* rather than at the end (P2).
                drop: { dragged in model.dropOnMember?(dragged, item) }
            )
        }
    }

    /// The group's name, as the thing you click to change it — the folder title on iOS, which is
    /// where everybody now looks for a rename (D104).
    @ViewBuilder
    private func header(_ group: SidebarGroup) -> some View {
        if model.isRenaming {
            nameField
        } else {
            HStack(spacing: 6) {
                Text(group.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .nexusRow(onClick: { model.beginRename() })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(group.name)
            .accessibilityHint(String(localized: "Renames the group"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.beginRename() }
        }
    }

    /// The title as a field. No row catcher over it: the click has to reach the field, and the
    /// panel is key for as long as the field is there, so it behaves like any other text field.
    private var nameField: some View {
        NativeSearchField(
            text: $model.draftName,
            placeholder: ApplicationCategory.fallbackName,
            fontSize: NSFont.preferredFont(forTextStyle: .headline).pointSize,
            onMove: { _ in },
            onSubmit: { _ in model.commitRename() },
            onCancel: { model.cancelRename() },
            focusesItself: true
        )
        .frame(height: 20)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
        }
        .accessibilityLabel(String(localized: "Group name"))
    }

    /// Colour and emoji, shown while the name is being edited — one place where everything about a
    /// group's appearance is changed, which is where iOS put it too (D108).
    private func styleEditor(_ group: SidebarGroup) -> some View {
        HStack(spacing: 6) {
            swatch(nil, isSelected: group.group.tint == nil)
            ForEach(GroupTint.allCases, id: \.rawValue) { tint in
                swatch(tint, isSelected: group.group.tint == tint)
            }
            Spacer(minLength: 0)
            NativeSearchField(
                text: $model.draftEmoji,
                placeholder: String(localized: "emoji"),
                fontSize: 13,
                onMove: { _ in },
                onSubmit: { _ in model.commitRename() },
                onCancel: { model.cancelRename() }
            )
            .frame(width: 34, height: 18)
            .padding(.horizontal, 4)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.quaternary)
            }
            .accessibilityLabel(String(localized: "Group emoji"))
        }
        .padding(.horizontal, 6)
    }

    private func swatch(_ tint: GroupTint?, isSelected: Bool) -> some View {
        Circle()
            .fill(tint?.color ?? Color.clear)
            .overlay {
                Circle().strokeBorder(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.separator),
                                      lineWidth: isSelected ? 1.5 : 0.5)
            }
            .overlay {
                // The "no colour" swatch says so, rather than being an empty circle nobody trusts.
                if tint == nil {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 14, height: 14)
            .contentShape(Circle())
            .nexusRow(onClick: { model.setTint(tint) })
            .accessibilityLabel(tint?.localizedName ?? String(localized: "No colour"))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.setTint(tint) }
    }
}

struct GroupMemberTile: View {
    let item: SidebarItem
    var layout: GroupLayout = .icons
    let launch: () -> Void
    let remove: () -> Void
    /// Another row was dropped on this tile (P2).
    var drop: ((String) -> Void)?

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
            }
            .contentShape(Rectangle())
            // Dragging a member out of the popover and onto the bar takes it out of the group: the
            // payload is the bundle identifier, so the bar's rows treat it like any other drag.
            .nexusRow(
                onClick: launch,
                menu: {
                    [
                        ClosureMenuItem(title: String(localized: "Open")) { launch() },
                        ClosureMenuItem(title: String(localized: "Remove from Group")) { remove() },
                    ]
                },
                dragPayload: item.id,
                dragImage: IconCache.shared.icon(for: item.bundleURL, size: 36),
                onDrop: drop
            )
            // After the tile's own catcher, deliberately: the topmost catcher wins, so a badge added
            // before it would sit underneath and its click would launch the application instead
            // (D104). Taking an application out by dragging it onto the bar is precise work with
            // nine or sixteen tiles in front of you; the badge is the same answer iOS gives.
            .nexusRemoveBadge(isHovered) { remove() }
            // Track the tile's geometry rather than its rendered SwiftUI layer. The badge has its own
            // AppKit click catcher; layer-sensitive `onHover` can report a false exit when that catcher
            // appears under the pointer, producing an endless hide/show flash (D110).
            .overlay {
                PanelHoverRegion { hovering in
                    withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                        isHovered = hovering
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name)
            .accessibilityHint(
                item.isRunning
                    ? String(localized: "Activates the application")
                    : String(localized: "Launches the application")
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { launch() }
    }

    /// The tile's face: an icon over a caption on the grid, an icon beside a name in the list.
    @ViewBuilder
    private var label: some View {
        switch layout {
        case .icons:
            VStack(spacing: 4) {
                icon(size: 36, dotOffset: 5)
                Text(item.name)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: GroupPopoverView.tileSize, height: GroupPopoverView.tileSize)
        case .list:
            HStack(spacing: 8) {
                icon(size: 20, dotOffset: 3)
                Text(item.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(
                width: GroupPopoverView.listWidth - GroupPopoverView.padding * 2,
                height: GroupPopoverView.listRowHeight,
                alignment: .leading
            )
        }
    }

    /// The icon with its running dot, and the anchor the remove badge hangs off.
    private func icon(size: CGFloat, dotOffset: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Image(nsImage: IconCache.shared.icon(for: item.bundleURL, size: size))
                .resizable()
                .frame(width: size, height: size)
            Circle()
                .fill(item.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: Design.runningDotDiameter, height: Design.runningDotDiameter)
                .offset(y: dotOffset)
                .opacity(item.isRunning ? 1 : 0)
        }
        .nexusIconAnchor()
    }
}
