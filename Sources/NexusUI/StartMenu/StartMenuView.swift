import AppKit
import NexusCore
import SwiftUI

public struct StartMenuView: View {
    @Bindable var model: StartMenuViewModel

    public static let width: CGFloat = 560
    public static let maximumHeight: CGFloat = 520
    public static let columns = 2
    public static let fieldHeight: CGFloat = 40
    public static let actionsHeight: CGFloat = 44

    /// Row anatomy is the search palette's, so the two panels read as one app.
    public static let rowHeight: CGFloat = 46
    public static let iconSize: CGFloat = 28
    public static let headerHeight: CGFloat = 22
    public static let listPadding: CGFloat = 6
    public static let cardPadding: CGFloat = 4
    public static let emptyPinnedHeight: CGFloat = 44

    /// Computed, not measured: a `LazyVGrid` inside a `ScrollView` has no intrinsic height, so
    /// `fittingSize` reports the chrome alone and the panel opens as a sliver.
    public static func height(pinned: Int, others: Int, showsPinnedSection: Bool) -> CGFloat {
        let otherRows = max(1, Int(ceil(Double(others) / Double(columns))))
        var content = listPadding * 2 + headerHeight + CGFloat(otherRows) * rowHeight
        if showsPinnedSection {
            let block = pinned > 0
                ? CGFloat(Int(ceil(Double(pinned) / Double(columns)))) * rowHeight + cardPadding * 2
                : emptyPinnedHeight
            content += headerHeight + block + Design.sectionSpacing
        }
        return min(maximumHeight, fieldHeight + actionsHeight + content + 2)
    }

    @Environment(\.colorSchemeContrast) private var contrast

    public init(model: StartMenuViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            field
            Divider()
            list
            Divider()
            actions
        }
        .frame(width: Self.width)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: contrast == .increased ? 1 : 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Applications"))
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            NativeSearchField(
                text: $model.query,
                placeholder: String(localized: "Search applications"),
                fontSize: 14,
                onMove: { model.moveSelection(by: $0, columns: Self.columns) },
                onSubmit: { _ in model.launchSelected() },
                onCancel: { model.close() }
            )
        }
        .padding(.horizontal, 14)
        .frame(height: Self.fieldHeight)
    }

    /// Two sections: what is on the bar, then everything else. Filtering collapses them into one
    /// flat set of matches, which is what a query asked for.
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !model.isFiltering {
                    header(String(localized: "Pinned"))
                    if model.pinnedCount > 0 {
                        rows(0..<model.pinnedCount)
                            .padding(Self.cardPadding)
                            .background {
                                RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                                    .fill(.quinary)
                            }
                            .padding(.horizontal, Self.listPadding)
                    } else {
                        emptyPinned
                    }
                    Spacer(minLength: 0)
                        .frame(height: Design.sectionSpacing)
                    header(String(localized: "All applications"))
                }
                rows(model.pinnedCount..<model.applications.count)
                    .padding(.horizontal, Self.listPadding)
            }
            .padding(.vertical, Self.listPadding)
        }
        .frame(maxHeight: Self.maximumHeight)
        .scrollIndicators(.automatic)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: Self.headerHeight, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// Kept even with nothing pinned, so the section does not appear out of nowhere the first time
    /// something is.
    private var emptyPinned: some View {
        Text("Nothing pinned yet. Right-click an application to pin it to the bar.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.emptyPinnedHeight)
            .background {
                RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                    .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .padding(.horizontal, Self.listPadding)
    }

    /// Resolved to values up front, and identified by the application rather than by its slot: a
    /// `ForEach` child that reaches back into the model runs once more after `reset()` empties it
    /// on the way out, and a stale index traps there — which took the whole app down (D110).
    public static func entries(
        _ range: Range<Int>,
        in applications: [NexusApplication]
    ) -> [(index: Int, application: NexusApplication)] {
        let safe = range.clamped(to: applications.indices)
        return safe.map { (index: $0, application: applications[$0]) }
    }

    private func rows(_ indices: Range<Int>) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: Self.columns),
            spacing: 0
        ) {
            ForEach(Self.entries(indices, in: model.applications), id: \.application.id) { entry in
                StartMenuRow(
                    application: entry.application,
                    isPinned: model.isPinned(entry.application),
                    isSelected: entry.index == model.selectedIndex,
                    action: { model.launch(entry.application) },
                    togglePin: { model.togglePin(entry.application) },
                    onHover: { model.selectedIndex = entry.index }
                )
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            ForEach(SystemAction.allCases, id: \.self) { action in
                SystemActionButton(action: action) { model.run(action) }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
    }
}

struct StartMenuRow: View {
    let application: NexusApplication
    let isPinned: Bool
    let isSelected: Bool
    let action: () -> Void
    let togglePin: () -> Void
    let onHover: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: IconCache.shared.icon(for: application.bundleURL, size: StartMenuView.iconSize))
                    .resizable()
                    .frame(width: StartMenuView.iconSize, height: StartMenuView.iconSize)
                Text(application.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            // Two hit targets side by side rather than one over the other: the row's click catcher
            // is an AppKit overlay, so a button drawn under it would never see the click (D88).
            .nexusRow(onClick: action, menu: menuItems)
            pin
        }
        .padding(.horizontal, 8)
        .frame(height: StartMenuView.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        }
        .onHover { hovering in
            isHovered = hovering
            guard hovering else { return }
            onHover()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(application.name)
        .accessibilityHint(
            application.isRunning
                ? String(localized: "Activates the application")
                : String(localized: "Launches the application")
        )
        .accessibilityAction { action() }
        .accessibilityAction(named: isPinned ? String(localized: "Unpin") : String(localized: "Pin")) {
            togglePin()
        }
    }

    /// Shown on every pinned row, and on hover for the rest — so the affordance is discoverable
    /// without the unpinned half of the list turning into a wall of glyphs.
    @ViewBuilder
    private var pin: some View {
        Image(systemName: isPinned ? "pin.fill" : "pin")
            .font(.system(size: 11))
            .foregroundStyle(isPinned ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .opacity(isPinned || isHovered ? 1 : 0)
            .frame(width: 20, height: StartMenuView.rowHeight)
            .contentShape(Rectangle())
            .nexusRow(onClick: togglePin)
            .help(isPinned ? String(localized: "Unpin from the bar") : String(localized: "Pin to the bar"))
            .accessibilityHidden(true)
    }

    private func menuItems() -> [NSMenuItem] {
        [
            ClosureMenuItem(title: isPinned ? String(localized: "Unpin") : String(localized: "Pin")) {
                togglePin()
            }
        ]
    }
}

struct SystemActionButton: View {
    let action: SystemAction
    let run: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: action.symbolName)
            Text(action.title)
                .font(.callout)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .nexusRow(onClick: run)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { run() }
    }
}
