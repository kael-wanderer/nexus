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
        // Three zones, and only the middle one scrolls (M14): with thirty applications running,
        // Trash and Search used to scroll off the end of the bar and have to be hunted for.
        content
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
        let zones = model.zones
        return axis {
            if model.showsStartMenuRow {
                startMenuRow
                separator
            }
            if model.showsPlaceholder {
                placeholder
            }
            if !model.pinned.isEmpty {
                scrolling(extent: zones.pinnedExtent) { pinnedSection }
            }
            if model.behavior.showRunningApplications, !model.running.isEmpty {
                if !model.pinned.isEmpty { separator }
                scrolling(extent: zones.runningExtent) { section(model.running) }
            }
            if !model.pinned.isEmpty || !model.running.isEmpty { separator }
            utilitySection
        }
        .padding(SidebarLayout.outerPadding)
        .frame(maxWidth: .infinity)
    }

    /// One section of the middle zone: it shows `extent` worth of rows and scrolls the rest inside
    /// itself, so a long list never pushes the zone below it off the bar.
    private func scrolling<Content: View>(
        extent: CGFloat,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        ScrollView(isVertical ? .vertical : .horizontal) {
            content()
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(
            width: isVertical ? nil : extent,
            height: isVertical ? extent : nil
        )
    }

    /// The pinned section draws groups (M13) and folders (M21) as well as applications.
    private var pinnedSection: some View {
        let spacing = model.appearance.iconSpacing
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        return layout {
            ForEach(model.pinned) { row in
                switch row {
                case .application(let item):
                    SidebarItemView(model: model, item: item, expanded: model.isExpanded)
                case .group(let group):
                    SidebarGroupView(model: model, group: group, expanded: model.isExpanded)
                case .folder(let folder):
                    SidebarFolderView(model: model, folder: folder, expanded: model.isExpanded)
                }
            }
        }
        .animation(
            Design.animation(Design.reveal, reduceMotion: reduceMotion),
            value: model.pinned.map(\.id)
        )
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
        // Rows are keyed by bundle identifier, so reordering the array is all SwiftUI needs to
        // slide them under the drag (D59). Reduce Motion drops the animation, not the reorder.
        .animation(Design.animation(Design.reveal, reduceMotion: reduceMotion), value: items.map(\.id))
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

    private var startMenuRow: some View {
        SidebarGlyphRow(
            systemImage: "square.grid.2x2",
            title: String(localized: "Applications"),
            iconSize: model.appearance.iconSize,
            expanded: model.isExpanded,
            isVertical: isVertical,
            hint: String(localized: "Opens the start menu"),
            isFocused: model.focusedRowID == SidebarViewModel.startMenuRowID
        ) {
            model.openStartMenu?()
        }
    }

    /// The fixed tail, as parts of its own: now playing when something is playing, the minimized
    /// windows when there are any, Trash, and Search. Each is separated, because they are different
    /// kinds of thing and the bar says so everywhere else (D77).
    private var utilitySection: some View {
        axis {
            if model.showsNowPlayingRow {
                if model.isMediaPlayerWide {
                    NowPlayingWidePlayer(model: model)
                } else {
                    NowPlayingRow(model: model, expanded: model.isExpanded)
                    NowPlayingControlsRow(model: model)
                }
                separator
            }
            if model.showsMinimizedRows {
                minimizedSection
                separator
            }
            trashRow
            if model.openSearch != nil {
                separator
                searchRow
            }
        }
    }

    /// Where a window goes when it is minimized: the owning application's icon, newest first, at
    /// most three (M22).
    private var minimizedSection: some View {
        let spacing = model.appearance.iconSpacing
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        return layout {
            ForEach(model.minimizedRows) { window in
                MinimizedWindowRow(model: model, window: window, expanded: model.isExpanded)
            }
        }
        .animation(
            Design.animation(Design.reveal, reduceMotion: reduceMotion),
            value: model.minimizedRows.map(\.id)
        )
    }

    private var trashRow: some View {
        SidebarGlyphRow(
            systemImage: "trash",
            image: TrashService.icon(empty: model.trashIsEmpty),
            title: String(localized: "Trash"),
            iconSize: model.appearance.iconSize,
            expanded: model.isExpanded,
            isVertical: isVertical,
            hint: String(localized: "Opens the Trash in Finder"),
            menu: {
                [
                    ClosureMenuItem(title: String(localized: "Open Trash")) { model.openTrash() },
                    ClosureMenuItem(title: String(localized: "Empty Trash…")) { confirmEmptyTrash() },
                ]
            },
            isFocused: model.focusedRowID == SidebarViewModel.trashRowID
        ) {
            model.openTrash()
        }
    }

    /// Emptying the Trash cannot be undone, so it asks first — the one confirmation in the
    /// sidebar, and the reason the menu item carries an ellipsis.
    private func confirmEmptyTrash() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Empty the Trash?")
        alert.informativeText = String(localized: "The items in the Trash will be deleted permanently.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Empty Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.emptyTrash()
    }

    @ViewBuilder
    private var searchRow: some View {
        if model.isSearchFieldWide {
            SidebarSearchBox(model: model)
        } else {
            searchIconRow
        }
    }

    private var searchIconRow: some View {
        SidebarGlyphRow(
            systemImage: "magnifyingglass",
            title: String(localized: "Search"),
            iconSize: model.appearance.iconSize,
            expanded: model.isExpanded,
            isVertical: isVertical,
            hint: String(localized: "Opens the Nexus search palette"),
            isFocused: model.focusedRowID == SidebarViewModel.searchRowID
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
                if model.behavior.showWindowCount, model.windowCountsAreExact, item.windowCount > 1 {
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
        .overlay {
            // The drag has been resting here long enough to mean "put these together" (M13).
            if model.groupCandidate == item.id {
                RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .nexusFocusRing(model.focusedRowID == item.id)
        .opacity(model.draggingIdentifier == item.id ? 0.35 : 1)
        .onHover { hovering in
            withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
            // Warms the window titles the context menu needs (D60) and drives the hover flyout.
            model.rowHoverChanged(item, hovering: hovering)
        }
        // The drag is AppKit's, not SwiftUI's: this panel can never become key, so
        // PanelRowInteraction claims every mouse-down and SwiftUI's own drag gestures never fire.
        .nexusRow(
            onClick: { model.activateOrLaunch(item) },
            menu: { contextMenuItems() },
            dragPayload: item.id,
            dragImage: IconCache.shared.icon(for: item.bundleURL, size: iconSize),
            onDrop: { dragged in model.dropPinned(dragged, on: item.id) },
            onDragBegin: { dragged in model.beginDrag(dragged) },
            onDragOver: { _, location in model.dragMoved(over: item.id, at: location) },
            onDragEnd: { accepted in model.endDrag(commit: accepted) }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(
            item.isRunning
                ? String(localized: "Activates the application")
                : String(localized: "Launches the application")
        )
        .accessibilityAddTraits(.isButton)
        // The click is AppKit's, so the row needs its own action or VoiceOver can read it and
        // not press it (D88).
        .accessibilityAction { model.activateOrLaunch(item) }
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
        if item.windowCount == 1 {
            return String(localized: "running, 1 window")
        }
        if item.windowCount > 1 {
            return String(localized: "running, \(item.windowCount) windows")
        }
        return String(localized: "running")
    }

    private func contextMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        // The application's windows, frontmost ticked, exactly where the Dock puts them (D60).
        let windows = model.windows(for: item.identity)
        for (index, window) in windows.enumerated() {
            let title = window.title.isEmpty ? item.name : window.title
            let entry = ClosureMenuItem(title: title) { model.activateWindow?(window.identity) }
            entry.state = item.isActive && index == 0 ? .on : .off
            entry.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
            items.append(entry)
        }
        if !windows.isEmpty { items.append(.separator()) }

        items.append(ClosureMenuItem(title: String(localized: "Open")) { model.activateOrLaunch(item) })
        if item.isRunning, model.showWindows != nil {
            items.append(
                ClosureMenuItem(title: String(localized: "Show All Windows")) {
                    model.openFlyout(for: item.identity)
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
        if model.isInGroup(item.id) {
            items.append(
                ClosureMenuItem(title: String(localized: "Remove from Group")) {
                    model.removeFromGroup(item.id)
                }
            )
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
/// render inactive in a window that can never become key (design/mvp.md §2.1).
struct SidebarGlyphRow: View {
    let systemImage: String
    /// Drawn instead of `systemImage` when present — the Trash row uses the macOS Trash icons.
    var image: NSImage?
    let title: String
    let iconSize: CGFloat
    let expanded: Bool
    let isVertical: Bool
    let hint: String
    var menu: () -> [NSMenuItem] = { [] }
    /// Whether the keyboard is on this row (M23).
    var isFocused = false
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = isVertical
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 2))
        return layout {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize * 0.5))
                }
            }
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
        .nexusFocusRing(isFocused)
        .onHover { hovering in
            withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
        }
        .nexusRow(onClick: action, menu: menu)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

/// The Search part drawn as a box rather than an icon (D90).
///
/// It looks like a field and is not one: this panel can never become key, so an `NSTextField` here
/// could not be typed into. Clicking it opens the palette beside the box, and the palette is where
/// the keystrokes go — which is the same bargain the start menu's filter field makes, one panel
/// along.
struct SidebarSearchBox: View {
    @Bindable var model: SidebarViewModel

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVertical: Bool { model.appearance.position.isVertical }

    /// Three rows' worth along the bar's axis, gaps included.
    private var extent: CGFloat {
        SidebarLayout.sectionExtent(rows: model.searchRowCount, appearance: model.appearance)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Search")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(
            width: isVertical ? nil : extent,
            height: isVertical ? SidebarLayout.rowHeight(model.appearance) : nil
        )
        .frame(maxWidth: isVertical ? .infinity : nil, maxHeight: isVertical ? nil : .infinity)
        .padding(isVertical ? .horizontal : .vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
                .padding(isVertical ? .horizontal : .vertical, 8)
        }
        .contentShape(Rectangle())
        .nexusFocusRing(model.focusedRowID == SidebarViewModel.searchRowID)
        .onHover { hovering in
            withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
        }
        .nexusRow(onClick: { model.openSearch?() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Search"))
        .accessibilityHint(String(localized: "Opens the Nexus search palette"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.openSearch?() }
    }
}
