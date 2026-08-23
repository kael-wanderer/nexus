import AppKit
import NexusCore
import SwiftUI

/// One minimized window in the tail (M22): the owning application's icon, drawn smaller than an
/// application row so the section reads as windows rather than as more applications, with the
/// window's title once the bar is expanded.
///
/// No thumbnail. A preview needs Screen Recording (M10), and a tile that is blank without a
/// permission is worse than one that is honestly an icon — the hover flyout still shows thumbnails
/// to anybody who granted it.
struct MinimizedWindowRow: View {
    @Bindable var model: SidebarViewModel
    let window: MinimizedWindow
    let expanded: Bool

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Smaller than an application icon, and never so small it stops being that application.
    private var iconSize: CGFloat { max(16, model.appearance.iconSize * 0.7) }
    private var isVertical: Bool { model.appearance.position.isVertical }

    var body: some View {
        let layout = isVertical
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 2))
        return layout {
            icon
            if expanded, isVertical {
                Text(window.name)
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
        .nexusFocusRing(model.focusedRowID == window.id)
        .onHover { hovering in
            withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
        }
        .nexusRow(
            onClick: { model.restore(window) },
            menu: {
                [ClosureMenuItem(title: String(localized: "Restore")) { model.restore(window) }]
            }
        )
        .help(window.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.name)
        .accessibilityValue(String(localized: "minimized · \(window.applicationName)"))
        .accessibilityHint(String(localized: "Restores the window"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.restore(window) }
    }

    private var icon: some View {
        Group {
            if let url = window.bundleURL {
                Image(nsImage: IconCache.shared.icon(for: url, size: iconSize))
                    .resizable()
            } else {
                Image(systemName: "macwindow")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: iconSize, height: iconSize)
    }
}
