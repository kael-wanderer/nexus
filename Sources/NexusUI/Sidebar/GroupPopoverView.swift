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

    /// Set by the composition root, so a click here does the same thing a click in the bar does.
    @ObservationIgnored public var launch: ((SidebarItem) -> Void)?
    @ObservationIgnored public var remove: ((SidebarItem) -> Void)?
    /// Commits a new name. Injected, because the dock belongs to the bar's model, not to this one.
    @ObservationIgnored public var rename: ((SidebarGroup, String) -> Void)?
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
}

public struct GroupPopoverView: View {
    @Bindable var model: GroupPopoverViewModel

    public static let tileSize: CGFloat = 76
    public static let padding: CGFloat = 10

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
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(Self.tileSize), spacing: 4),
                    count: model.columns
                ),
                spacing: 4
            ) {
                ForEach(group.items) { item in
                    GroupMemberTile(
                        item: item,
                        launch: { model.launch?(item) },
                        remove: { model.remove?(item) }
                    )
                }
            }
        }
        .padding(Self.padding)
        .frame(width: CGFloat(model.columns) * (Self.tileSize + 4) + Self.padding * 2)
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
}

/// Where the icon sits inside its tile, so the remove badge can be drawn on the tile's own layer —
/// above the click catcher — and still land on the icon's corner.
private struct IconCorner: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct GroupMemberTile: View {
    let item: SidebarItem
    let launch: () -> Void
    let remove: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Image(nsImage: IconCache.shared.icon(for: item.bundleURL, size: 36))
                    .resizable()
                    .frame(width: 36, height: 36)
                Circle()
                    .fill(item.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: Design.runningDotDiameter, height: Design.runningDotDiameter)
                    .offset(y: 5)
                    .opacity(item.isRunning ? 1 : 0)
            }
            .anchorPreference(key: IconCorner.self, value: .bounds) { $0 }
            Text(item.name)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: GroupPopoverView.tileSize, height: GroupPopoverView.tileSize)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
        }
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
            dragImage: IconCache.shared.icon(for: item.bundleURL, size: 36)
        )
        // After the tile's own catcher, deliberately: `nexusRow` overlays an `NSView` on whatever it
        // is applied to, so a badge added before it sits *under* the tile's click catcher and the
        // click launches the application instead of removing it. The topmost catcher wins, so the
        // badge has to be the last thing on the tile.
        .overlayPreferenceValue(IconCorner.self) { anchor in
            // Taking an application out by dragging it onto the bar is precise work with nine or
            // sixteen tiles in front of you. The badge is the same answer iOS gives.
            if isHovered, let anchor {
                GeometryReader { proxy in
                    let icon = proxy[anchor]
                    RemoveBadge(action: remove)
                        .position(x: icon.minX, y: icon.minY)
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
}

/// The minus badge that takes an application out of a group. Its own row rather than a `Button`,
/// because AppKit controls render inactive in a panel that can never become key.
struct RemoveBadge: View {
    let action: () -> Void

    var body: some View {
        Image(systemName: "minus.circle.fill")
            .font(.system(size: 16))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .secondary)
            .background(Circle().fill(.background).padding(2))
            .contentShape(Circle())
            .nexusRow(onClick: action)
            .accessibilityLabel(String(localized: "Remove from group"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

