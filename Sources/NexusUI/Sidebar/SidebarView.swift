import AppKit
import NexusCore
import SwiftUI

public struct SidebarView: View {
    @Bindable var model: SidebarViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    public init(model: SidebarViewModel) {
        self.model = model
    }

    private var isVertical: Bool { model.appearance.position.isVertical }

    public var body: some View {
        // The frame is clamped to the screen (SidebarLayout.frame), so with enough running
        // applications the content is longer than the panel. Scrolling is what keeps the last
        // rows reachable instead of clipped off the end.
        ScrollView(isVertical ? .vertical : .horizontal) {
            content
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: model.appearance.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: model.appearance.cornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: contrast == .increased ? 1 : 0.5)
        }
        .opacity(model.appearance.opacity)
        .animation(Design.animation(Design.reveal, reduceMotion: reduceMotion), value: model.isExpanded)
        .onHover { model.hoverChanged($0) }
        .dropDestination(for: URL.self) { urls, _ in model.pinApplications(at: urls) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Nexus sidebar"))
    }

    /// The bar's axis, applied to every stack in it. `AnyLayout` swaps the axis without
    /// duplicating the view tree.
    private var axis: AnyLayout {
        isVertical
            ? AnyLayout(VStackLayout(spacing: SidebarLayout.separatorSpacing))
            : AnyLayout(HStackLayout(spacing: SidebarLayout.separatorSpacing))
    }

    private var content: some View {
        axis {
            if model.showsPlaceholder {
                placeholder
            }
            if !model.pinned.isEmpty {
                section(model.pinned)
            }
            if model.behavior.showRunningApplications, !model.running.isEmpty {
                if !model.pinned.isEmpty { separator }
                section(model.running)
            }
            if model.openSearch != nil {
                if !model.pinned.isEmpty || !model.running.isEmpty { separator }
                searchRow
            }
        }
        .padding(SidebarLayout.outerPadding)
        .frame(maxWidth: .infinity)
    }

    private func section(_ items: [SidebarItem]) -> some View {
        let spacing = model.appearance.iconSpacing
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        return layout {
            ForEach(items) { item in
                SidebarItemView(model: model, item: item, expanded: model.isExpanded)
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(.separator)
            .frame(
                width: isVertical ? nil : Design.separatorHeight,
                height: isVertical ? Design.separatorHeight : nil
            )
            .padding(isVertical ? .horizontal : .vertical, 4)
            .accessibilityHidden(true)
    }

    private var searchRow: some View {
        SidebarGlyphRow(
            systemImage: "magnifyingglass",
            title: String(localized: "Search"),
            iconSize: model.appearance.iconSize,
            expanded: model.isExpanded,
            isVertical: isVertical,
            hint: String(localized: "Opens the Nexus search palette")
        ) {
            model.openSearch?()
        }
    }

    private var placeholder: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus.app.dashed")
                .font(.system(size: model.appearance.iconSize * 0.5))
                .foregroundStyle(.tertiary)
            if model.isExpanded {
                Text("Drag applications here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: isVertical ? nil : SidebarLayout.rowHeight(model.appearance),
            height: isVertical ? SidebarLayout.rowHeight(model.appearance) : nil
        )
        .frame(maxWidth: isVertical ? .infinity : nil, maxHeight: isVertical ? nil : .infinity)
        .accessibilityLabel(String(localized: "No pinned applications"))
        .accessibilityHint(String(localized: "Drag an application here to pin it"))
    }
}

struct SidebarItemView: View {
    @Bindable var model: SidebarViewModel
    let item: SidebarItem
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
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: IconCache.shared.icon(for: item.bundleURL, size: iconSize))
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                if model.behavior.showWindowCount, item.windowCount > 1 {
                    Text("\(item.windowCount)")
                        .font(.system(size: max(8, iconSize * 0.24), weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            if expanded, isVertical {
                Text(item.name)
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
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
        }
        // ponytail: no drag-to-reorder. A row cannot start a SwiftUI drag here — the panel never
        // becomes key, so PanelRowInteraction has to claim every mouse-down for the click to work
        // at all. Reordering is the Move Up / Move Down / Move to End menu items; add an AppKit
        // dragging session in PanelRowInteraction if dragging is wanted.
        .nexusRow(onClick: { model.activateOrLaunch(item) }, menu: { contextMenuItems() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(
            item.isRunning
                ? String(localized: "Activates the application")
                : String(localized: "Launches the application")
        )
        .accessibilityAddTraits(.isButton)
    }

    private var runningIndicator: some View {
        Circle()
            .fill(item.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(
                width: Design.runningDotDiameter,
                height: Design.runningDotDiameter
            )
            .opacity(item.isRunning ? 1 : 0)
            .accessibilityHidden(true)
    }

    private var backgroundStyle: AnyShapeStyle {
        if item.isActive { return AnyShapeStyle(.quaternary) }
        if isHovered { return AnyShapeStyle(.quinary) }
        return AnyShapeStyle(.clear)
    }

    private var accessibilityValue: String {
        guard item.isRunning else { return String(localized: "not running") }
        if item.windowCount > 0 {
            return String(localized: "running, \(item.windowCount) windows")
        }
        return String(localized: "running")
    }

    private func contextMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = [
            ClosureMenuItem(title: String(localized: "Open")) { model.activateOrLaunch(item) }
        ]
        if item.isRunning, model.showWindows != nil {
            items.append(
                ClosureMenuItem(title: String(localized: "Show Windows")) {
                    model.showWindows?(item.identity)
                }
            )
        }
        items.append(.separator())
        if item.isPinned {
            items.append(ClosureMenuItem(title: String(localized: "Unpin")) { model.unpin(item.id) })
            items.append(
                ClosureMenuItem(title: String(localized: "Move Up"), isEnabled: model.canMovePinned(item.id, by: -1)) {
                    model.movePinned(item.id, by: -1)
                }
            )
            items.append(
                ClosureMenuItem(title: String(localized: "Move Down"), isEnabled: model.canMovePinned(item.id, by: 1)) {
                    model.movePinned(item.id, by: 1)
                }
            )
            items.append(
                ClosureMenuItem(title: String(localized: "Move to End")) {
                    model.movePinnedToEnd(item.id)
                }
            )
        } else {
            items.append(ClosureMenuItem(title: String(localized: "Pin")) { model.pin(item.id) })
        }
        items.append(
            ClosureMenuItem(title: String(localized: "Show in Finder")) { model.revealInFinder(item) }
        )
        if item.isRunning {
            items.append(.separator())
            items.append(
                ClosureMenuItem(title: String(localized: "Quit")) { model.quit(item, force: false) }
            )
            items.append(
                ClosureMenuItem(title: String(localized: "Force Quit")) { model.quit(item, force: true) }
            )
        }
        return items
    }
}

/// A non-application row (search). Custom-drawn, no `Button` chrome, because AppKit controls
/// render inactive in a window that can never become key (DESIGN_MVP §2.1).
struct SidebarGlyphRow: View {
    let systemImage: String
    let title: String
    let iconSize: CGFloat
    let expanded: Bool
    let isVertical: Bool
    let hint: String
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = isVertical
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 2))
        return layout {
            Image(systemName: systemImage)
                .font(.system(size: iconSize * 0.5))
                .frame(width: iconSize, height: iconSize)
            if expanded, isVertical {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(isVertical ? .horizontal : .vertical, 4)
        .frame(width: isVertical ? nil : iconSize + 8, height: isVertical ? iconSize + 8 : nil)
        .frame(maxWidth: isVertical ? .infinity : nil, maxHeight: isVertical ? nil : .infinity)
        .background {
            RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
        }
        .nexusRow(onClick: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
    }
}
