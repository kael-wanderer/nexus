import NexusCore
import SwiftUI

public struct StartMenuView: View {
    @Bindable var model: StartMenuViewModel

    public static let width: CGFloat = 560
    public static let maximumHeight: CGFloat = 520
    public static let columns = 4
    public static let tileHeight: CGFloat = 84
    public static let fieldHeight: CGFloat = 40
    public static let actionsHeight: CGFloat = 44
    public static let gridPadding: CGFloat = 20
    public static let tileSpacing: CGFloat = 4

    /// Computed, not measured: a `LazyVGrid` inside a `ScrollView` has no intrinsic height, so
    /// `fittingSize` reports the chrome alone and the panel opens as a sliver.
    public static func height(forApplications count: Int) -> CGFloat {
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        let grid = CGFloat(rows) * tileHeight + CGFloat(max(0, rows - 1)) * tileSpacing + gridPadding
        return min(maximumHeight, fieldHeight + actionsHeight + grid + 2)
    }

    @Environment(\.colorSchemeContrast) private var contrast

    public init(model: StartMenuViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            field
            Divider()
            grid
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

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 4),
                    count: Self.columns
                ),
                spacing: 4
            ) {
                ForEach(Array(model.applications.enumerated()), id: \.element.id) { index, application in
                    StartMenuTile(
                        application: application,
                        isSelected: index == model.selectedIndex,
                        action: { model.launch(application) },
                        onHover: { model.selectedIndex = index }
                    )
                }
            }
            .padding(10)
        }
        .frame(maxHeight: Self.maximumHeight)
        .scrollIndicators(.automatic)
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

struct StartMenuTile: View {
    let application: NexusApplication
    let isSelected: Bool
    let action: () -> Void
    let onHover: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: IconCache.shared.icon(for: application.bundleURL, size: 40))
                .resizable()
                .frame(width: 40, height: 40)
            Text(application.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(height: StartMenuView.tileHeight)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            guard hovering else { return }
            onHover()
        }
        .nexusRow(onClick: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(application.name)
        .accessibilityHint(
            application.isRunning
                ? String(localized: "Activates the application")
                : String(localized: "Launches the application")
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
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
