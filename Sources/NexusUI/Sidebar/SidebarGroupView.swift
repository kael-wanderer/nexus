import AppKit
import NexusCore
import SwiftUI

/// A group's row: the first four member icons on a 2×2 grid inside a rounded tile, which is what
/// both iOS and Launchpad do and what stays readable at 40 pt (M13).
struct SidebarGroupView: View {
    @Bindable var model: SidebarViewModel
    let group: SidebarGroup
    let expanded: Bool

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var iconSize: CGFloat { model.appearance.iconSize }
    private var isVertical: Bool { model.appearance.position.isVertical }
    private var isGroupTarget: Bool { model.groupCandidate == group.id }

    var body: some View {
        let layout = isVertical
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 2))
        return layout {
            tile
            if expanded, isVertical {
                Text(group.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            runningIndicator
        }
        .padding(isVertical ? .horizontal : .vertical, 4)
        .frame(
            width: isVertical ? nil : SidebarLayout.rowHeight(model.appearance),
            height: isVertical ? SidebarLayout.rowHeight(model.appearance) : nil
        )
        .frame(maxWidth: isVertical ? .infinity : nil, maxHeight: isVertical ? nil : .infinity)
        .background {
            RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                .fill(backgroundStyle)
        }
        .overlay {
            if isGroupTarget {
                RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .nexusFocusRing(model.focusedRowID == group.id)
        .opacity(model.draggingIdentifier == group.id ? 0.35 : 1)
        .onHover { hovering in
            withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
        }
        .nexusRow(
            onClick: { model.openGroup(group) },
            menu: { contextMenuItems() },
            dragPayload: group.id,
            dragImage: GroupIcon.image(for: group.items.map(\.bundleURL), size: iconSize),
            onDrop: { dragged in model.dropPinned(dragged, on: group.id) },
            onDragBegin: { dragged in model.beginDrag(dragged) },
            onDragOver: { _ in model.dragMoved(over: group.id) },
            onDragEnd: { accepted in model.endDrag(commit: accepted) }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(group.name)
        .accessibilityValue(
            String(localized: "group of \(group.items.count) applications")
        )
        .accessibilityHint(String(localized: "Opens the group"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.openGroup(group) }
    }

    private var tile: some View {
        let inset = iconSize * 0.08
        let cell = (iconSize - inset * 3) / 2
        return RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous)
            .fill(.quaternary)
            .frame(width: iconSize, height: iconSize)
            .overlay {
                Grid(horizontalSpacing: inset, verticalSpacing: inset) {
                    GridRow {
                        memberIcon(0, size: cell)
                        memberIcon(1, size: cell)
                    }
                    GridRow {
                        memberIcon(2, size: cell)
                        memberIcon(3, size: cell)
                    }
                }
            }
    }

    private func memberIcon(_ index: Int, size: CGFloat) -> some View {
        Group {
            if let item = group.items.indices.contains(index) ? group.items[index] : nil {
                Image(nsImage: IconCache.shared.icon(for: item.bundleURL, size: size))
                    .resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }

    private var runningIndicator: some View {
        Circle()
            .fill(group.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: Design.runningDotDiameter, height: Design.runningDotDiameter)
            .opacity(group.isRunning ? 1 : 0)
            .accessibilityHidden(true)
    }

    private var backgroundStyle: AnyShapeStyle {
        if isHovered { return AnyShapeStyle(.quinary) }
        return AnyShapeStyle(.clear)
    }

    private func contextMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = [
            ClosureMenuItem(title: String(localized: "Open Group")) { model.openGroup(group) }
        ]
        for item in group.items {
            let entry = ClosureMenuItem(title: item.name) { model.activateOrLaunch(item) }
            entry.image = IconCache.shared.icon(for: item.bundleURL, size: 16)
            items.append(entry)
        }
        items.append(.separator())
        items.append(ClosureMenuItem(title: String(localized: "Rename…")) { promptForName() })
        items.append(
            ClosureMenuItem(title: String(localized: "Ungroup")) { model.ungroup(group.id) }
        )
        items.append(
            ClosureMenuItem(title: String(localized: "Remove Group")) { model.unpinGroup(group.id) }
        )
        items.append(.separator())
        items.append(
            ClosureMenuItem(title: String(localized: "Move Up"), isEnabled: model.canMovePinned(group.id, by: -1)) {
                model.movePinned(group.id, by: -1)
            }
        )
        items.append(
            ClosureMenuItem(title: String(localized: "Move Down"), isEnabled: model.canMovePinned(group.id, by: 1)) {
                model.movePinned(group.id, by: 1)
            }
        )
        items.append(
            ClosureMenuItem(title: String(localized: "Move to End")) { model.movePinnedToEnd(group.id) }
        )
        return items
    }

    private func promptForName() {
        GroupRename.prompt(for: group, model: model)
    }
}

/// The drag image for a group: the same 2×2 tile the row draws, flattened into one `NSImage`.
@MainActor
enum GroupIcon {
    static func image(for members: [URL], size: CGFloat) -> NSImage {
        let image = NSImage(size: CGSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }
        let inset = size * 0.08
        let cell = (size - inset * 3) / 2
        for (index, url) in members.prefix(4).enumerated() {
            let column = CGFloat(index % 2)
            let row = CGFloat(index / 2)
            // AppKit draws bottom-up; the first icon belongs top-left.
            let origin = CGPoint(
                x: inset + column * (cell + inset),
                y: size - inset - cell - row * (cell + inset)
            )
            IconCache.shared
                .icon(for: url, size: cell)
                .draw(in: CGRect(origin: origin, size: CGSize(width: cell, height: cell)))
        }
        return image
    }
}
