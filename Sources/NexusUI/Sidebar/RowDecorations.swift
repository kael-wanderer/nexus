import AppKit
import NexusCore
import SwiftUI

/// The small pieces every row of the bar can wear: the insertion caret a drag draws between two
/// rows, the badge the Dock says an application is carrying, the shake of edit mode, and the puff of
/// smoke a row leaves when it is dragged off (M24).
///
/// One file because they are one idea — decoration on a row — and because the application row, the
/// group row and the folder row all need the same ones.
extension Design {
    /// The caret drawn where a reorder would land (P1). Three points, tinted, and inset a little so
    /// it reads as *between* two rows rather than as an edge of one.
    public static let dropIndicatorThickness: CGFloat = 3

    /// How far a row leans while it jiggles, and how far an icon travels when its application is
    /// launching. Small numbers: this is a bar somebody works next to all day.
    public static let jiggleDegrees: Double = 2.2
    public static let launchBounce: CGFloat = 7

    public static let jiggle = Animation.easeInOut(duration: 0.16).repeatForever(autoreverses: true)
    public static let bounce = Animation.easeOut(duration: 0.22).repeatCount(3, autoreverses: true)

    /// The minus badge is a fixed size rather than whatever the symbol measures, because where it
    /// goes is arithmetic and arithmetic needs a number (D110).
    public static let removeBadgeDiameter: CGFloat = 18

    /// Where the badge's centre goes: the icon's top-left corner, pulled in far enough that the
    /// whole badge stays inside the row it decorates.
    ///
    /// The pulling-in is the fix, not a nicety (D110). A badge that hangs over the row's edge hangs
    /// outside the row's *hover region* too, so moving the pointer onto it read as leaving the row —
    /// which hid the badge, which put the pointer back over the row, which showed it again. That
    /// loop is what flashed.
    public static func removeBadgeCentre(icon: CGRect, in size: CGSize) -> CGPoint {
        let radius = removeBadgeDiameter / 2
        return CGPoint(
            x: min(max(icon.minX, radius), max(size.width - radius, radius)),
            y: min(max(icon.minY, radius), max(size.height - radius, radius))
        )
    }
}

/// A colour picked for a group (D108), as the system's own semantic colour rather than a hex value,
/// so dark mode and Increase Contrast are somebody else's problem.
extension GroupTint {
    /// The colour's own name, for the context menu and for VoiceOver — a swatch nobody can read out
    /// loud is a control only some people have.
    public var localizedName: String {
        switch self {
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        }
    }

    public var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }
}

extension View {
    /// The insertion caret for a drag that would land on this row's leading or trailing edge (P1).
    /// `nil` draws nothing. The edge follows the bar's axis, so the same code draws a horizontal
    /// line under a row of a vertical bar and a vertical line beside one of a horizontal bar.
    @ViewBuilder
    public func nexusDropIndicator(after: Bool?, isVertical: Bool) -> some View {
        if let after {
            overlay(alignment: indicatorAlignment(after: after, isVertical: isVertical)) {
                Capsule()
                    .fill(.tint)
                    .frame(
                        width: isVertical ? nil : Design.dropIndicatorThickness,
                        height: isVertical ? Design.dropIndicatorThickness : nil
                    )
                    .padding(isVertical ? .horizontal : .vertical, 4)
                    .accessibilityHidden(true)
            }
        } else {
            self
        }
    }

    private func indicatorAlignment(after: Bool, isVertical: Bool) -> Alignment {
        if isVertical { return after ? .bottom : .top }
        return after ? .trailing : .leading
    }

    /// Edit mode's shake (D107). Reduce Motion gets the minus badges and no movement — the badge is
    /// what says the row can be removed; the shake only says it louder.
    public func nexusJiggle(_ active: Bool, reduceMotion: Bool) -> some View {
        rotationEffect(.degrees(active && !reduceMotion ? Design.jiggleDegrees : 0))
            .animation(active && !reduceMotion ? Design.jiggle : nil, value: active)
    }
}

/// Where the icon sits inside its row or tile, so a badge can be drawn on the *topmost* layer and
/// still land on the icon's corner.
///
/// The layer matters: `nexusRow` overlays an `NSView` to catch clicks, so anything added before it
/// sits underneath and its clicks go to the row instead (D104). A preference anchor is how the badge
/// gets both — the icon's position and the top of the stack.
struct IconCorner: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Marks this view as the row's icon, for whatever wants to decorate its corner.
    func nexusIconAnchor() -> some View {
        anchorPreference(key: IconCorner.self, value: .bounds) { $0 }
    }

    /// The minus badge, on the icon's top-left corner and above every other layer. Apply it *after*
    /// `nexusRow`, or the row's own catcher swallows the click.
    @ViewBuilder
    func nexusRemoveBadge(_ visible: Bool, action: @escaping () -> Void) -> some View {
        overlayPreferenceValue(IconCorner.self) { anchor in
            if visible, let anchor {
                GeometryReader { proxy in
                    RemoveBadge(action: action)
                        .position(Design.removeBadgeCentre(icon: proxy[anchor], in: proxy.size))
                }
            }
        }
    }
}

/// The minus badge that takes something out: an application out of a group, or a row off the bar in
/// edit mode. Its own row rather than a `Button`, because AppKit controls render inactive in a panel
/// that can never become key.
struct RemoveBadge: View {
    let action: () -> Void

    var body: some View {
        Image(systemName: "minus.circle.fill")
            .font(.system(size: 16))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .secondary)
            .background(Circle().fill(.background).padding(2))
            .frame(width: Design.removeBadgeDiameter, height: Design.removeBadgeDiameter)
            .contentShape(Circle())
            .nexusRow(onClick: action)
            .accessibilityLabel(String(localized: "Remove"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// The red badge the Dock draws on an application with something waiting (D106). Mirrored as text,
/// never parsed: "9999+" is a badge somebody shipped, and so is "!".
struct DockBadge: View {
    let label: String
    /// The icon this sits on the corner of, so the badge scales with it.
    let iconSize: CGFloat

    var body: some View {
        Text(label)
            .font(.system(size: max(8, iconSize * 0.22), weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, max(3, iconSize * 0.07))
            .padding(.vertical, 1)
            .background(Capsule().fill(.red))
            .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// The puff of smoke the Dock shows when something is dragged off it (F1, D105).
///
/// `NSAnimationEffect.disappearingItemDefault` *is* the poof, drawn by AppKit at whatever point on
/// screen it is given, with no view or window of its own. It is old API and exactly right: the
/// alternative is animating a sprite in a panel that has just been told to forget the row.
@MainActor
enum Poof {
    static func show(at screenPoint: NSPoint) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        NSAnimationEffect.disappearingItemDefault.show(
            centeredAt: screenPoint,
            size: NSSize(width: 32, height: 32)
        )
    }
}
