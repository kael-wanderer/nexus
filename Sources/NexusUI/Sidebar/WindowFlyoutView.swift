import NexusCore
import SwiftUI

public struct WindowFlyoutView: View {
    @Bindable var model: WindowFlyoutViewModel
    let permissions: any PermissionChecking

    public static let width: CGFloat = 320
    public static let rowHeight: CGFloat = 30
    public static let previewHeight: CGFloat = 96
    /// Past this many windows the cards scroll instead of running off the screen.
    public static let maximumCards = 5

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
        VStack(alignment: .leading, spacing: 10) {
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
        .frame(width: model.isVertical ? Self.width : nil, alignment: .leading)
        .flyoutPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Windows of \(model.applicationName)"))
    }

    /// Side-by-side thumbnails, the shape the Dock uses above or below a horizontal bar.
    private var cards: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(model.windows) { window in
                    WindowCard(model: model, window: window)
                }
            }
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(
            maxWidth: CGFloat(min(model.windows.count, Self.maximumCards))
                * (model.flyoutSize.cardSize.width + 10),
            alignment: .leading
        )
    }

    /// The application's icon and name, and two buttons: Quit, and New Window (§4 of the flyout
    /// restyle). Both live on the view model, not here — a header button is a trigger, not a place
    /// to decide what pressing it does.
    private var header: some View {
        FlyoutHeader(icon: model.applicationIcon, name: model.applicationName) {
            HStack(spacing: 2) {
                FlyoutHeaderButton(
                    symbol: "macwindow.badge.plus",
                    label: String(localized: "New window")
                ) {
                    model.newWindow()
                }
                FlyoutHeaderButton(
                    symbol: "power",
                    label: String(localized: "Quit \(model.applicationName)")
                ) {
                    model.quit()
                }
            }
        }
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
    }
}

/// A small round icon button for the flyout header — Quit and New Window are the only two callers,
/// and neither needs anything `FlatActionRow`'s text pill offers.
private struct FlyoutHeaderButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 26, height: 26)
            .background {
                Circle().fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                    isHovered = hovering
                }
            }
            .nexusRow(onClick: action)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
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
                Text(window.displayTitle)
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
        .accessibilityLabel(window.displayTitle)
        .accessibilityValue(
            window.isMinimized ? String(localized: "minimized") : String(localized: "open")
        )
        .accessibilityHint(String(localized: "Brings this window to the front"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.activate(window) }
    }
}

/// One window as a full-bleed thumbnail with its title as a chip over the bottom-leading corner —
/// the horizontal counterpart of `WindowRow`, which stacks beside a vertical bar. Restyled from a
/// thumbnail-plus-caption card to match the reference: the caption moved onto the image, and a
/// hovered card gets an accent ring instead of a tinted background.
struct WindowCard: View {
    @Bindable var model: WindowFlyoutViewModel
    let window: NexusWindow

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var size: CGSize { model.flyoutSize.cardSize }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let preview = model.previews[window.identity.number] {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // No Screen Recording, or the capture has not arrived yet. A neutral tile,
                    // never an error-looking placeholder (§3.5).
                    RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: window.isMinimized ? "minus.rectangle" : "macwindow")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous))

            LabelChip(window.displayTitle)
                .padding(8)
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                .strokeBorder(
                    isHovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear),
                    lineWidth: 2
                )
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
        .accessibilityLabel(window.displayTitle)
        .accessibilityValue(
            window.isMinimized ? String(localized: "minimized") : String(localized: "open")
        )
        .accessibilityHint(String(localized: "Brings this window to the front"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.activate(window) }
    }
}
