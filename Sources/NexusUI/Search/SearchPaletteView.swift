import AppKit
import NexusCore
import SwiftUI

public struct SearchPaletteView: View {
    @Bindable var model: SearchViewModel
    @Environment(\.colorSchemeContrast) private var contrast

    public static let width: CGFloat = 640
    public static let fieldHeight: CGFloat = 52
    public static let rowHeight: CGFloat = 46
    public static let headerHeight: CGFloat = 22
    public static let maximumListHeight: CGFloat = 420

    public init(model: SearchViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            field
            if !model.results.isEmpty {
                Divider()
                list
            }
        }
        .frame(width: Self.width)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: contrast == .increased ? 1 : 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Nexus search"))
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            NativeSearchField(
                text: $model.query,
                placeholder: String(localized: "Search apps, files, windows…"),
                fontSize: 20,
                onMove: { model.moveSelection(by: $0) },
                onSubmit: { model.execute(secondary: $0) },
                onCancel: { model.close() }
            )
            .frame(height: 26)
            if model.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "Searching"))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Self.fieldHeight)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.groupedResults, id: \.category) { group in
                        Text(group.category.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .frame(height: Self.headerHeight, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.results) { result in
                            SearchResultRow(
                                result: result,
                                isSelected: result.id == model.selectedID,
                                positionLabel: positionLabel(for: result)
                            )
                            .id(result.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.click(result) }
                            .onHover { if $0 { model.select(result) } }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: Self.maximumListHeight)
            .onChange(of: model.selectedID) { _, newValue in
                guard let newValue else { return }
                proxy.scrollTo(newValue, anchor: .center)
            }
        }
    }

    private func positionLabel(for result: SearchResult) -> String? {
        guard let index = model.results.firstIndex(where: { $0.id == result.id }), index < 9
        else { return nil }
        return "⌘\(index + 1)"
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    let positionLabel: String?

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if let positionLabel {
                Text(positionLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: SearchPaletteView.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
                .padding(.horizontal, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.title)
        .accessibilityValue(result.subtitle ?? result.category.title)
        .accessibilityHint(String(localized: "Press Return to run this result"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var icon: some View {
        switch result.icon {
        case .application(let url), .file(let url):
            Image(nsImage: IconCache.shared.icon(for: url, size: 28))
                .resizable()
                .frame(width: 28, height: 28)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
    }
}
