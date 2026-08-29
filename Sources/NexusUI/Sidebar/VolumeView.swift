import NexusCore
import SwiftUI

/// The volume control at the end of the bar: one slot, the speaker glyph for the current state,
/// opening a slider (M27).
///
/// Left click opens the slider, right click mutes — the same split the Trash row makes between
/// "show me" and "act now", and it keeps mute one gesture away rather than behind the popover.
struct SidebarVolumeRow: View {
    @Bindable var model: SidebarViewModel

    var body: some View {
        SidebarGlyphRow(
            systemImage: model.volume.symbolName,
            title: String(localized: "Volume"),
            iconSize: model.appearance.iconSize,
            expanded: model.isExpanded,
            isVertical: model.appearance.position.isVertical,
            hint: String(localized: "Opens the volume slider"),
            menu: {
                [
                    ClosureMenuItem(
                        title: model.volume.isMuted
                            ? String(localized: "Unmute")
                            : String(localized: "Mute")
                    ) { model.volume.toggleMute() }
                ]
            },
            isFocused: model.focusedRowID == SidebarViewModel.volumeRowID
        ) {
            model.showVolume?()
        }
        // The glyph says which of three bands the level is in; VoiceOver gets the number.
        .accessibilityValue(
            model.volume.isMuted
                ? Text(String(localized: "Muted"))
                : Text(Double(model.volume.level), format: .percent.precision(.fractionLength(0)))
        )
    }
}

/// The slider the volume row opens.
struct VolumePopoverView: View {
    @Bindable var model: SidebarViewModel

    private var level: Binding<Double> {
        Binding(
            get: { Double(model.volume.level) },
            set: { model.volume.setLevel(Float($0)) }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.volume.toggleMute()
            } label: {
                Image(systemName: model.volume.symbolName)
                    .font(.system(size: 13))
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                model.volume.isMuted ? String(localized: "Unmute") : String(localized: "Mute")
            )

            Slider(value: level, in: 0...1)
                .frame(width: 140)
                .accessibilityLabel(String(localized: "Volume"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
