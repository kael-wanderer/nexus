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

    /// Deliberately not just the application's icon: the same application usually has a row of its
    /// own a few slots up, and two identical icons read as a duplicate rather than as a player. The
    /// artwork is inset on a tinted tile with a waveform badge, so the row says "this is what is
    /// playing" at a glance.
    private var artwork: some View {
        let inset = iconSize * 0.18
        return ZStack {
            RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous)
                .fill(.tint.opacity(0.22))
            Image(nsImage: model.nowPlayingArtwork(size: iconSize - inset * 2))
                .resizable()
                .frame(width: iconSize - inset * 2, height: iconSize - inset * 2)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.14, style: .continuous))
            if isHovered {
                RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous)
                    .fill(.black.opacity(0.5))
                Image(systemName: playing.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: iconSize * 0.36))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: iconSize * 0.24, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(2)
                    .background(Circle().fill(.tint))
                    .offset(x: iconSize * 0.28, y: iconSize * 0.28)
            }
            if let position = model.nowPlayingPosition, position.hasTimeline {
                progress(position)
            }
        }
        .frame(width: iconSize, height: iconSize)
    }

    /// How far through, on the tile itself: a two-point line along the bottom edge. The bar has no
    /// room for a scrubber, and the popover is where dragging happens — but "half way through" is
    /// worth knowing without hovering anything.
    private func progress(_ position: MediaPosition) -> some View {
        VStack {
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.35)).frame(height: 3)
                Capsule()
                    .fill(.tint)
                    .frame(width: max(2, (iconSize - 8) * position.fraction), height: 3)
            }
            .frame(width: iconSize - 8)
            .padding(.bottom, 3)
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

/// The hover flyout: what is playing, the three controls, and a timeline where the player will
/// report one (M16). Same rules as the window flyout — it never takes focus, so the scrubber is a
/// drag target rather than an `NSSlider`.
@MainActor
@Observable
public final class NowPlayingPopoverViewModel {
    public private(set) var playing = NowPlaying()
    public private(set) var isShowing = false
    public private(set) var position: MediaPosition?
    /// Where the thumb is while a drag is in progress, so the clock reads the target rather than the
    /// second-old truth.
    public var dragFraction: Double?

    @ObservationIgnored public var artwork: (CGFloat) -> NSImage = { _ in NSImage() }
    @ObservationIgnored public var toggle: () -> Void = {}
    @ObservationIgnored public var next: () -> Void = {}
    @ObservationIgnored public var previous: () -> Void = {}
    @ObservationIgnored public var seek: (Double) -> Void = { _ in }
    @ObservationIgnored public var onDismiss: (() -> Void)?

    public init() {}

    public func show(_ playing: NowPlaying, position: MediaPosition?) {
        self.playing = playing
        self.position = position
        isShowing = true
    }

    /// Keeps the open flyout in step with the track: a change of song must not leave the previous
    /// one on screen.
    public func update(_ playing: NowPlaying, position: MediaPosition?) {
        guard isShowing else { return }
        self.playing = playing
        // A reading arriving mid-drag must not yank the thumb out from under the pointer.
        if dragFraction == nil { self.position = position }
    }

    public func hide() {
        guard isShowing else { return }
        isShowing = false
        dragFraction = nil
        onDismiss?()
    }

    public var hasTimeline: Bool { position?.hasTimeline == true }

    /// What the track draws: the drag if there is one, the reading otherwise.
    public var fraction: Double { dragFraction ?? position?.fraction ?? 0 }

    public var elapsedText: String {
        MediaPosition.clock((position?.duration ?? 0) * fraction)
    }

    public var remainingText: String {
        let duration = position?.duration ?? 0
        return "-" + MediaPosition.clock(duration - duration * fraction)
    }

    /// A drop seeks once, to where the pointer is. Seeking per pixel would be an AppleScript round
    /// trip per pixel, and a player that stutters.
    public func endDrag() {
        guard let dragFraction, let duration = position?.duration else { return }
        self.dragFraction = nil
        seek(duration * dragFraction)
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
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            if model.hasTimeline {
                Timeline(model: model)
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

/// The scrubber. Drawn rather than built from `NSSlider`, because AppKit controls render inactive
/// in a window that can never become key (`design/mvp.md` §2.1) — and because the drag has to seek
/// once on release rather than continuously.
private struct Timeline: View {
    @Bindable var model: NowPlayingPopoverViewModel

    private let height: CGFloat = 4
    private let thumb: CGFloat = 11

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: height)
                    Capsule()
                        .fill(.tint)
                        .frame(width: max(0, width * model.fraction), height: height)
                    Circle()
                        .fill(.white)
                        .shadow(radius: 1, y: 0.5)
                        .frame(width: thumb, height: thumb)
                        .offset(x: max(0, min(width - thumb, width * model.fraction - thumb / 2)))
                }
                .frame(height: thumb)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            model.dragFraction = min(max(value.location.x / width, 0), 1)
                        }
                        .onEnded { _ in model.endDrag() }
                )
            }
            .frame(height: thumb)
            HStack {
                Text(model.elapsedText)
                Spacer(minLength: 4)
                Text(model.remainingText)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Timeline"))
        .accessibilityValue(model.elapsedText)
    }
}

/// The controls, as a row of their own in the bar (M16): the three buttons a player needs, without
/// a hover. Sized to fit across a 64 pt bar, and laid out along whichever axis the bar runs.
struct NowPlayingControlsRow: View {
    @Bindable var model: SidebarViewModel

    private var isVertical: Bool { model.appearance.position.isVertical }
    private var iconSize: CGFloat { model.appearance.iconSize }

    var body: some View {
        let layout = isVertical
            ? AnyLayout(HStackLayout(spacing: 2))
            : AnyLayout(HStackLayout(spacing: 2))
        return layout {
            button("backward.fill", String(localized: "Previous")) { model.previousTrack() }
            button(
                model.nowPlaying.isPlaying ? "pause.fill" : "play.fill",
                model.nowPlaying.isPlaying ? String(localized: "Pause") : String(localized: "Play")
            ) { model.togglePlayback() }
            button("forward.fill", String(localized: "Next")) { model.nextTrack() }
        }
        .frame(
            width: isVertical ? nil : SidebarLayout.rowHeight(model.appearance),
            height: isVertical ? SidebarLayout.rowHeight(model.appearance) : nil
        )
        .frame(maxWidth: isVertical ? .infinity : nil, maxHeight: isVertical ? nil : .infinity)
    }

    private func button(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        MiniTransportButton(symbol: symbol, label: label, size: iconSize / 3 - 2, action: action)
    }
}

struct MiniTransportButton: View {
    let symbol: String
    let label: String
    let size: CGFloat
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: max(8, size * 0.5)))
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
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

/// The wide player (M17): a small icon, the progress bar or the track name, and the three transport
/// buttons, inline in the bar. One view spanning four rows' worth of extent, which is what keeps the
/// rest of the layout maths row-based.
struct NowPlayingWidePlayer: View {
    @Bindable var model: SidebarViewModel

    @State private var isHovered = false
    @State private var dragFraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var iconSize: CGFloat { model.appearance.iconSize }
    private var isVertical: Bool { model.appearance.position.isVertical }
    private var playing: NowPlaying { model.nowPlaying }
    private var position: MediaPosition? { model.nowPlayingPosition }

    /// Four rows' worth along the bar's axis, gaps included.
    private var extent: CGFloat {
        SidebarLayout.sectionExtent(rows: model.nowPlayingRowCount, appearance: model.appearance)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: model.nowPlayingArtwork(size: 18))
                .resizable()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            middle
            controls
        }
        .padding(.horizontal, 8)
        .frame(
            width: isVertical ? nil : extent,
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(playing.title ?? String(localized: "Now playing"))
    }

    /// Progress or the name, whichever the setting says — and the name when there is no progress to
    /// show, because an empty track is worse than a title nobody asked for.
    @ViewBuilder
    private var middle: some View {
        if model.appearance.mediaContent == .progress, let position, position.hasTimeline {
            InlineTimeline(
                position: position,
                dragFraction: $dragFraction,
                onSeek: { model.seekPlayback(to: $0) }
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(playing.title ?? String(localized: "Playing"))
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let artist = playing.artist {
                    Text(artist)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controls: some View {
        HStack(spacing: 2) {
            MiniTransportButton(symbol: "backward.fill", label: String(localized: "Previous"), size: 22) {
                model.previousTrack()
            }
            MiniTransportButton(
                symbol: playing.isPlaying ? "pause.fill" : "play.fill",
                label: playing.isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                size: 22
            ) {
                model.togglePlayback()
            }
            MiniTransportButton(symbol: "forward.fill", label: String(localized: "Next"), size: 22) {
                model.nextTrack()
            }
        }
    }
}

/// The bar's own scrubber. Coarser than the popover's — a 40-minute film across 200 points is about
/// twelve seconds per point — so the popover stays for precision.
private struct InlineTimeline: View {
    let position: MediaPosition
    @Binding var dragFraction: Double?
    let onSeek: (Double) -> Void

    private var fraction: Double { dragFraction ?? position.fraction }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 4)
                    Capsule().fill(.tint).frame(width: max(0, width * fraction), height: 4)
                    Circle()
                        .fill(.white)
                        .shadow(radius: 1, y: 0.5)
                        .frame(width: 9, height: 9)
                        .offset(x: max(0, min(width - 9, width * fraction - 4.5)))
                }
                .frame(height: 10)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { dragFraction = min(max($0.location.x / width, 0), 1) }
                        .onEnded { _ in
                            if let dragFraction { onSeek(position.duration * dragFraction) }
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 10)
            HStack {
                Text(MediaPosition.clock(position.duration * fraction))
                Spacer(minLength: 4)
                Text("-" + MediaPosition.clock(position.duration - position.duration * fraction))
            }
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Timeline"))
        .accessibilityValue(MediaPosition.clock(position.position))
    }
}
