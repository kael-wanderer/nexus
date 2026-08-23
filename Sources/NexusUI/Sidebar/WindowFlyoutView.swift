import NexusCore
import SwiftUI

public struct WindowFlyoutView: View {
    @Bindable var model: WindowFlyoutViewModel
    let permissions: any PermissionChecking

    public static let width: CGFloat = 320
    public static let rowHeight: CGFloat = 30
    public static let headerHeight: CGFloat = 26
    public static let previewHeight: CGFloat = 96
    /// One card beside a horizontal bar: a thumbnail with its title underneath.
    public static let cardWidth: CGFloat = 200
    /// Past this many windows the cards scroll instead of running off the screen.
    public static let maximumCards = 5

    @Environment(\.colorSchemeContrast) private var contrast

    public init(model: WindowFlyoutViewModel, permissions: any PermissionChecking) {
        self.model = model
        self.permissions = permissions
    }

    public var body: some View {
        // An `NSHostingView` evaluates its body as soon as it is constructed, whether or not its
        // panel is on screen. Gating the whole flyout on `target` is what keeps the permission
        // screen's 1 Hz poll scoped to a *visible* screen (D13) instead of running for the
        // lifetime of the app.
        if model.target != nil {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.showsPermissionRequest {
                PermissionRequestView(
                    permission: .accessibility,
                    permissions: permissions,
                    onGrantTapped: { model.requestAccessibility() },
                    onDismiss: { model.hide() }
                )
            } else {
                header
                if model.windows.isEmpty {
                    Text("No windows")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: Self.rowHeight)
                } else if model.isVertical {
                    ForEach(model.windows) { window in
                        WindowRow(model: model, window: window)
                    }
                } else {
                    cards
                }
                if model.showsPreviewsOffer { previewsOffer }
            }
        }
        .padding(8)
        .frame(width: model.isVertical ? Self.width : nil, alignment: .leading)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: contrast == .increased ? 1 : 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Windows of \(model.applicationName)"))
    }

    /// Side-by-side thumbnails, the shape the Dock uses above or below a horizontal bar.
    private var cards: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(model.windows) { window in
                    WindowCard(model: model, window: window)
                }
            }
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(
            maxWidth: CGFloat(min(model.windows.count, Self.maximumCards))
                * (Self.cardWidth + 8),
            alignment: .leading
        )
    }

    private var header: some View {
        Text(model.applicationName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: Self.headerHeight, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var previewsOffer: some View {
        HStack(spacing: 8) {
            Text("Enable window previews?")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            FlatActionRow(title: String(localized: "Enable"), prominent: false) {
                model.requestScreenRecording()
            }
            FlatActionRow(title: String(localized: "No Thanks"), prominent: false) {
                model.dismissPreviewsOffer()
            }
        }
        .padding(.horizontal, 6)
    }
}

struct WindowRow: View {
    @Bindable var model: WindowFlyoutViewModel
    let window: NexusWindow

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: window.isMinimized ? "minus.rectangle" : "macwindow")
                    .foregroundStyle(.secondary)
                Text(displayTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: WindowFlyoutView.rowHeight)

            if let preview = model.previews[window.identity.number] {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: WindowFlyoutView.previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.horizontal, 8)
                    .accessibilityHidden(true)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
            if hovering { model.requestPreview(for: window) }
        }
        .nexusRow(onClick: { model.activate(window) })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayTitle)
        .accessibilityValue(
            window.isMinimized ? String(localized: "minimized") : String(localized: "open")
        )
        .accessibilityHint(String(localized: "Brings this window to the front"))
        .accessibilityAddTraits(.isButton)
    }

    private var displayTitle: String {
        window.title.isEmpty ? String(localized: "Untitled window") : window.title
    }
}

/// One window as a thumbnail with its title underneath — the horizontal counterpart of
/// `WindowRow`, which stacks them beside a vertical bar.
struct WindowCard: View {
    @Bindable var model: WindowFlyoutViewModel
    let window: NexusWindow

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let preview = model.previews[window.identity.number] {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    // No Screen Recording, or the capture has not arrived yet. A neutral tile,
                    // never an error-looking placeholder (§3.5).
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: window.isMinimized ? "minus.rectangle" : "macwindow")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: WindowFlyoutView.cardWidth, height: WindowFlyoutView.previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)

            Text(displayTitle)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: WindowFlyoutView.cardWidth, alignment: .leading)
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
            if hovering { model.requestPreview(for: window) }
        }
        .nexusRow(onClick: { model.activate(window) })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayTitle)
        .accessibilityValue(
            window.isMinimized ? String(localized: "minimized") : String(localized: "open")
        )
        .accessibilityHint(String(localized: "Brings this window to the front"))
        .accessibilityAddTraits(.isButton)
    }

    private var displayTitle: String {
        window.title.isEmpty ? String(localized: "Untitled window") : window.title
    }
}
