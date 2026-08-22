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

    public var body: some View {
        VStack(spacing: SidebarLayout.separatorSpacing) {
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

    private func section(_ items: [SidebarItem]) -> some View {
        VStack(spacing: model.appearance.iconSpacing) {
            ForEach(items) { item in
                SidebarItemView(model: model, item: item, expanded: model.isExpanded)
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: Design.separatorHeight)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }

    private var searchRow: some View {
        SidebarGlyphRow(
            systemImage: "magnifyingglass",
            title: String(localized: "Search"),
            iconSize: model.appearance.iconSize,
            expanded: model.isExpanded,
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
        .frame(height: SidebarLayout.rowHeight(model.appearance))
        .frame(maxWidth: .infinity)
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

    var body: some View {
        HStack(spacing: 8) {
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
            if expanded {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            runningIndicator
        }
        .padding(.horizontal, 4)
        .frame(height: SidebarLayout.rowHeight(model.appearance))
        .frame(maxWidth: .infinity)
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
        .onTapGesture { model.activateOrLaunch(item) }
        .draggable(item.id) {
            Image(nsImage: IconCache.shared.icon(for: item.bundleURL, size: iconSize))
        }
        .dropDestination(for: String.self) { identifiers, _ in
            guard let dragged = identifiers.first else { return false }
            model.movePinned(dragged, before: item.id)
            return true
        }
        .nexusContextMenu { contextMenuItems() }
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
    let hint: String
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize * 0.5))
                .frame(width: iconSize, height: iconSize)
            if expanded {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: iconSize + 8)
        .frame(maxWidth: .infinity)
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
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
    }
}
