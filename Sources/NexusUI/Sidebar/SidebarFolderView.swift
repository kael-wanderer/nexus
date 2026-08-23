import AppKit
import NexusCore
import SwiftUI

/// A pinned folder's row: the folder's own icon, which is what makes a Downloads stack look like
/// Downloads (M21). No running dot and no window count — a folder is not running.
struct SidebarFolderView: View {
    @Bindable var model: SidebarViewModel
    let folder: SidebarFolder
    let expanded: Bool

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var iconSize: CGFloat { model.appearance.iconSize }
    private var isVertical: Bool { model.appearance.position.isVertical }

    var body: some View {
        let layout = isVertical
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 2))
        return layout {
            Image(nsImage: IconCache.shared.icon(for: folder.url, size: iconSize))
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .nexusIconAnchor()
            if expanded, isVertical {
                Text(folder.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(isVertical ? .horizontal : .vertical, 4)
        .frame(
            width: isVertical ? nil : SidebarLayout.rowHeight(model.appearance),
            height: isVertical ? SidebarLayout.rowHeight(model.appearance) : nil
        )
        .frame(maxWidth: isVertical ? .infinity : nil, maxHeight: isVertical ? nil : .infinity)
        .background {
            RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear))
        }
        .contentShape(Rectangle())
        .nexusFocusRing(model.focusedRowID == folder.id)
        .nexusDropIndicator(after: model.dropEdge(for: folder.id), isVertical: isVertical)
        .nexusJiggle(model.isEditing, reduceMotion: reduceMotion)
        .opacity(model.draggingIdentifier == folder.id ? 0.35 : 1)
        .onHover { hovering in
            withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
            // Resting on a folder shows what is in it, when the preference asks for it (F2).
            model.folderHoverChanged(folder, hovering: hovering)
        }
        .nexusRow(
            onClick: { click() },
            menu: { contextMenuItems() },
            dragPayload: folder.id,
            dragImage: IconCache.shared.icon(for: folder.url, size: iconSize),
            onDrop: { dragged in model.dropPinned(dragged, on: folder.id) },
            onDragBegin: { dragged in model.beginDrag(dragged) },
            onDragOver: { _, location in model.dragMoved(over: folder.id, at: location) },
            onDragEnd: { accepted in model.endDrag(commit: accepted) },
            onDragOut: { point in
                if model.dragDroppedOutside() { Poof.show(at: point) }
            },
            onLongPress: { model.beginEditing() }
        )
        .nexusRemoveBadge(model.isEditing) { model.removeRow(folder.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(folder.name)
        .accessibilityValue(String(localized: "folder"))
        .accessibilityHint(String(localized: "Shows what is in the folder"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.openFolder(folder) }
    }

    private func click() {
        guard !model.isEditing else {
            model.endEditing()
            return
        }
        model.openFolder(folder)
    }

    private func contextMenuItems() -> [NSMenuItem] {
        [
            ClosureMenuItem(title: String(localized: "Show Contents")) { model.openFolder(folder) },
            ClosureMenuItem(title: String(localized: "Open in Finder")) {
                NSWorkspace.shared.open(folder.url)
            },
            .separator(),
            ClosureMenuItem(title: String(localized: "Remove from Bar")) {
                model.unpinFolder(folder.id)
            },
            .separator(),
            ClosureMenuItem(
                title: String(localized: "Move Up"),
                isEnabled: model.canMovePinned(folder.id, by: -1)
            ) { model.movePinned(folder.id, by: -1) },
            ClosureMenuItem(
                title: String(localized: "Move Down"),
                isEnabled: model.canMovePinned(folder.id, by: 1)
            ) { model.movePinned(folder.id, by: 1) },
            ClosureMenuItem(title: String(localized: "Move to End")) {
                model.movePinnedToEnd(folder.id)
            },
        ]
    }
}
