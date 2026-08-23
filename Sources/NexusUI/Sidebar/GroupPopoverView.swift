import AppKit
import NexusCore
import SwiftUI

/// What a group looks like when opened: its applications on a grid, beside the bar (M13).
///
/// Like the window flyout, this panel can never become key — so it holds no text field, and
/// renaming lives in the row's context menu instead of a header nobody could type into.
@MainActor
@Observable
public final class GroupPopoverViewModel {
    public private(set) var group: SidebarGroup?

    /// Set by the composition root, so a click here does the same thing a click in the bar does.
    @ObservationIgnored public var launch: ((SidebarItem) -> Void)?
    @ObservationIgnored public var remove: ((SidebarItem) -> Void)?
    @ObservationIgnored public var onDismiss: (() -> Void)?

    public init() {}

    public func show(_ group: SidebarGroup) {
        self.group = group
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
            Text(group.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
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
