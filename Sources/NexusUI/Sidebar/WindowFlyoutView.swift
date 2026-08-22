import NexusCore
import SwiftUI

public struct WindowFlyoutView: View {
    @Bindable var model: WindowFlyoutViewModel
    let permissions: any PermissionChecking

    public static let width: CGFloat = 320
    public static let rowHeight: CGFloat = 30
    public static let headerHeight: CGFloat = 26
    public static let previewHeight: CGFloat = 96

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
                } else {
                    ForEach(model.windows) { window in
                        WindowRow(model: model, window: window)
                    }
                }
                if model.showsPreviewsOffer { previewsOffer }
            }
        }
        .padding(8)
        .frame(width: Self.width, alignment: .leading)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: contrast == .increased ? 1 : 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Windows of \(model.applicationName)"))
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
