import AppKit
import NexusCore
import SwiftUI

/// What a pinned folder looks like when opened: its contents on a grid, beside the bar (M21).
///
/// Same panel rules as the group popover — it can never become key, so there is no text field and
/// no rename here either.
@MainActor
@Observable
public final class FolderStackViewModel {
    public private(set) var folder: SidebarFolder?
    public private(set) var listing: FolderListing = .items([])

    /// Injected so tests do not need a directory on disk.
    @ObservationIgnored public var read: (URL) -> FolderListing = { FolderStackService.list($0) }
    /// Set by the composition root: opening a file is the system's business, not this type's.
    @ObservationIgnored public var open: ((URL) -> Void)?
    @ObservationIgnored public var onDismiss: (() -> Void)?

    public init() {}

    public func show(_ folder: SidebarFolder) {
        self.folder = folder
        listing = read(folder.url)
    }

    /// Called after every dock edit: the popover follows its folder, and closes if that folder
    /// stopped being pinned.
    public func update(from rows: [SidebarRow]) {
        guard let current = folder else { return }
        guard rows.contains(where: { $0.folder?.id == current.id }) else {
            hide()
            return
        }
    }

    public func hide() {
        guard folder != nil else { return }
        folder = nil
        listing = .items([])
        onDismiss?()
    }

    /// Three across for a short listing, four beyond it — the same shape the group popover uses.
    public var columns: Int { listing.items.count > 9 ? 4 : 3 }
}

public struct FolderStackView: View {
    @Bindable var model: FolderStackViewModel

    public static let tileSize: CGFloat = 76
    public static let padding: CGFloat = 10

    public init(model: FolderStackViewModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if let folder = model.folder {
                content(folder)
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
        .accessibilityLabel(model.folder?.name ?? String(localized: "Folder"))
    }

    private func content(_ folder: SidebarFolder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(folder)
            switch model.listing {
            case .items(let items) where items.isEmpty:
                message(String(localized: "Empty"))
            case .items(let items):
                grid(items)
            case .refused:
                refusal(folder)
            case .missing:
                message(String(localized: "This folder is no longer there"))
            }
        }
        .padding(Self.padding)
        .frame(width: CGFloat(model.columns) * (Self.tileSize + 4) + Self.padding * 2)
    }

    private func header(_ folder: SidebarFolder) -> some View {
        HStack(spacing: 6) {
            Text(folder.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if case .items(let items) = model.listing, !items.isEmpty {
                Text(
                    items.count == 1
                        ? String(localized: "1 item")
                        : String(localized: "\(items.count) items")
                )
                .font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func grid(_ items: [FolderItem]) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(Self.tileSize), spacing: 4),
                count: model.columns
            ),
            spacing: 4
        ) {
            ForEach(items) { item in
                FolderItemTile(item: item, open: { model.open?(item.url) })
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
    }

    /// A folder macOS will not let Nexus read is not an empty folder, and saying so is only half
    /// the answer: opening it in Finder is both what the user wanted and what makes macOS ask
    /// again.
    private func refusal(_ folder: SidebarFolder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Nexus needs permission to read this folder"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "Open in Finder")) { model.open?(folder.url) }
                .controlSize(.small)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

struct FolderItemTile: View {
    let item: FolderItem
    let open: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: IconCache.shared.icon(for: item.url, size: 36))
                .resizable()
                .frame(width: 36, height: 36)
            Text(item.name)
                .font(.caption2)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
        }
        .frame(width: FolderStackView.tileSize, height: FolderStackView.tileSize)
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
        .nexusRow(
            onClick: open,
            menu: {
                [
                    ClosureMenuItem(title: String(localized: "Open")) { open() },
                    ClosureMenuItem(title: String(localized: "Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    },
                ]
            },
            dragPayload: nil,
            dragImage: nil
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(
            item.isDirectory ? String(localized: "folder") : String(localized: "file")
        )
        .accessibilityHint(
            item.isDirectory
                ? String(localized: "Opens the folder in Finder")
                : String(localized: "Opens the file")
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }
}
