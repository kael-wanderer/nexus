import AppKit
import NexusCore
import SwiftUI

/// Chrome the two hover panels share — the window flyout's cards and the now-playing panel — so
/// they read as one family rather than two popovers that happen to float beside the bar. Three
/// pieces: the panel's own frame, its header, and the caption chip both panels overlay on an
/// image. Nothing here belongs to one panel more than the other; a piece one of them stops needing
/// belongs in that panel's own file, not here.
private struct FlyoutPanelModifier: ViewModifier {
    static let cornerRadius: CGFloat = 24

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(VisualEffectBackground(material: .popover))
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                // The same hairline the flyout drew before this restyle, Increase Contrast doubled
                // the way every other panel border in Nexus is (`design/mvp.md` §9).
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(.separator, lineWidth: contrast == .increased ? 1 : 0.5)
            }
    }
}

extension View {
    /// The 24 pt rounded card, the material, and the hairline border both flyouts wear.
    public func flyoutPanel() -> some View {
        modifier(FlyoutPanelModifier())
    }
}

/// The application's — or the player's — icon and name, with room on the trailing edge for
/// whatever buttons the caller needs. Both flyouts open with this and nothing else.
public struct FlyoutHeader<Actions: View>: View {
    let icon: NSImage
    let name: String
    let actions: () -> Actions

    public init(icon: NSImage, name: String, @ViewBuilder actions: @escaping () -> Actions) {
        self.icon = icon
        self.name = name
        self.actions = actions
    }

    public var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // One element with the name as its label: VoiceOver reads "<name>, heading" once,
            // rather than the icon and the text as two stops that both say the same thing.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            actions()
        }
    }
}

/// White text on a dark rounded tile, for a caption overlaid on an image: the window's title over
/// its thumbnail, the track's title over its artwork.
///
/// Hidden from VoiceOver on purpose. Whatever draws the chip already carries the same text as its
/// own accessibility label — the card, the artwork block — and a chip that spoke for itself too
/// would read the title twice.
public struct LabelChip: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.black.opacity(0.55))
            }
            .accessibilityHidden(true)
    }
}

/// The one place the two flyouts' sizes are numbers: `behavior.flyoutSize` (Settings → Bar) picks
/// the case, everything else reads it from here. Medium is the reference screenshot's measurements;
/// small and large are even steps either side, not independently tuned.
extension FlyoutSize {
    public var cardSize: CGSize {
        switch self {
        case .small: CGSize(width: 260, height: 160)
        case .medium: CGSize(width: 340, height: 210)
        case .large: CGSize(width: 420, height: 260)
        }
    }

    public var artworkSize: CGFloat {
        switch self {
        case .small: 150
        case .medium: 190
        case .large: 230
        }
    }

    public var tileSize: CGSize {
        switch self {
        case .small: CGSize(width: 76, height: 38)
        case .medium: CGSize(width: 96, height: 48)
        case .large: CGSize(width: 116, height: 58)
        }
    }
}
