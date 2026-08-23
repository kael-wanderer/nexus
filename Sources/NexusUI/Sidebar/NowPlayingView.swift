import AppKit
import NexusCore
import SwiftUI

/// The now-playing row, in the bar's fixed tail (M15). Artwork — or the player's own icon, which is
/// the only image macOS will give a third party — with a play/pause overlay on hover.
struct NowPlayingRow: View {
    @Bindable var model: SidebarViewModel
    let expanded: Bool

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var iconSize: CGFloat { model.appearance.iconSize }
    private var isVertical: Bool { model.appearance.position.isVertical }
    private var playing: NowPlaying { model.nowPlaying }

    var body: some View {
        let layout = isVertical
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 2))
        return layout {
            artwork
            if expanded, isVertical {
                VStack(alignment: .leading, spacing: 0) {
                    Text(playing.title ?? String(localized: "Playing"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let artist = playing.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(isVertical ? .horizontal : .vertical, 4)
        .frame(
            width: isVertical ? nil : SidebarLayout.rowHeight(model.appearance),
            height: isVertical ? SidebarLayout.rowHeight(model.appearance) : nil
        )
        .frame(maxWidth: isVertical ? .infinity : nil, maxHeight: isVertical ? nil : .infinity)
        .background {
            RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
            model.nowPlayingHoverChanged(hovering)
        }
        .nexusRow(
            onClick: { model.togglePlayback() },
            menu: { menuItems() }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(String(localized: "Plays or pauses"))
        .accessibilityAddTraits(.isButton)
    }

    private var artwork: some View {
        ZStack {
            Image(nsImage: model.nowPlayingArtwork(size: iconSize))
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.2, style: .continuous))
            if isHovered {
                RoundedRectangle(cornerRadius: iconSize * 0.2, style: .continuous)
                    .fill(.black.opacity(0.45))
                Image(systemName: playing.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: iconSize * 0.4))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: iconSize, height: iconSize)
    }

    private var accessibilityLabel: String {
        guard let title = playing.title else { return String(localized: "Now playing") }
        guard let artist = playing.artist else { return title }
        return "\(title), \(artist)"
    }

    private func menuItems() -> [NSMenuItem] {
        [
            ClosureMenuItem(title: playing.isPlaying
                ? String(localized: "Pause")
                : String(localized: "Play")) { model.togglePlayback() },
            ClosureMenuItem(title: String(localized: "Next")) { model.nextTrack() },
            ClosureMenuItem(title: String(localized: "Previous")) { model.previousTrack() },
        ]
    }
}

/// The hover flyout: what is playing, and the three controls. Same rules as the window flyout —
/// it never takes focus, so it holds no text field and no scrubber.
@MainActor
@Observable
public final class NowPlayingPopoverViewModel {
    public private(set) var playing = NowPlaying()
    public private(set) var isShowing = false

    @ObservationIgnored public var artwork: (CGFloat) -> NSImage = { _ in NSImage() }
    @ObservationIgnored public var toggle: () -> Void = {}
    @ObservationIgnored public var next: () -> Void = {}
    @ObservationIgnored public var previous: () -> Void = {}
    @ObservationIgnored public var onDismiss: (() -> Void)?

    public init() {}

    public func show(_ playing: NowPlaying) {
        self.playing = playing
        isShowing = true
    }

    /// Keeps the open flyout in step with the track: a change of song must not leave the previous
    /// one on screen.
    public func update(_ playing: NowPlaying) {
        guard isShowing else { return }
        self.playing = playing
    }

    public func hide() {
        guard isShowing else { return }
        isShowing = false
        onDismiss?()
    }
}

public struct NowPlayingPopoverView: View {
    @Bindable var model: NowPlayingPopoverViewModel

    public static let artworkSize: CGFloat = 120

    public init(model: NowPlayingPopoverViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: model.artwork(Self.artworkSize))
                .resizable()
                .frame(width: Self.artworkSize, height: Self.artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(spacing: 2) {
                Text(model.playing.title ?? String(localized: "Playing"))
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let artist = model.playing.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                control("backward.fill", String(localized: "Previous")) { model.previous() }
                control(
                    model.playing.isPlaying ? "pause.fill" : "play.fill",
                    model.playing.isPlaying ? String(localized: "Pause") : String(localized: "Play")
                ) { model.toggle() }
                control("forward.fill", String(localized: "Next")) { model.next() }
            }
        }
        .padding(12)
        .frame(width: 180)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Now playing"))
    }

    /// Custom-drawn, not an `NSButton`: AppKit controls render inactive in a window that can never
    /// become key (`design/mvp.md` §2.1).
    private func control(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        TransportButton(symbol: symbol, label: label, action: action)
    }
}

private struct TransportButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14))
            .frame(width: 44, height: 30)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
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
    }
}
