import CoreGraphics
import NexusCore

/// Panel geometry derived from configuration and item counts. Pure, so the panel frame is known
/// without a SwiftUI measurement round-trip — and so it can be unit-tested.
///
/// One axis vocabulary covers all four edges: **extent** is the length along the bar (its height
/// when vertical, its width when horizontal) and **thickness** is the other one. Only
/// `SidebarPosition.isVertical` decides which is which; nothing below branches on the individual
/// edges except to pick which side of the screen to sit on.
public enum SidebarLayout {
    public static let outerPadding: CGFloat = 8
    public static let expandedWidth: CGFloat = 220
    public static let separatorSpacing: CGFloat = 6
    public static let screenMargin: CGFloat = 8
    public static let edgeTriggerWidth: CGFloat = 2

    /// One row's size along the bar's axis.
    public static func rowHeight(_ appearance: AppearanceConfiguration) -> CGFloat {
        appearance.iconSize + 8
    }

    /// Thickness across the bar. Hover-expand is vertical-only (D53): growing a horizontal bar's
    /// height on hover would shove every window on the screen.
    public static func width(_ appearance: AppearanceConfiguration, expanded: Bool) -> CGFloat {
        expanded && appearance.position.isVertical
            ? max(expandedWidth, appearance.width)
            : appearance.width
    }

    /// Length along the bar's axis. `sectionRowCounts` lists the rows in each visible section, in
    /// order. Empty sections must not be passed in — separators are drawn between the sections
    /// that are actually there.
    public static func height(
        sectionRowCounts: [Int],
        appearance: AppearanceConfiguration
    ) -> CGFloat {
        let sections = sectionRowCounts.filter { $0 > 0 }
        guard !sections.isEmpty else { return rowHeight(appearance) + outerPadding * 2 }

        let row = rowHeight(appearance)
        let spacing = CGFloat(appearance.iconSpacing)
        let rows = sections.reduce(0, +)
        let withinSectionGaps = sections.reduce(0) { $0 + max(0, $1 - 1) }
        let separators = max(0, sections.count - 1)

        return outerPadding * 2
            + CGFloat(rows) * row
            + CGFloat(withinSectionGaps) * spacing
            + CGFloat(separators) * (Design.separatorHeight + separatorSpacing * 2)
    }

    public static func size(
        sectionRowCounts: [Int],
        appearance: AppearanceConfiguration,
        expanded: Bool
    ) -> CGSize {
        let extent = height(sectionRowCounts: sectionRowCounts, appearance: appearance)
        let thickness = width(appearance, expanded: expanded)
        return appearance.position.isVertical
            ? CGSize(width: thickness, height: extent)
            : CGSize(width: extent, height: thickness)
    }

    /// Frame on the given visible area, clamped so the panel never runs off screen and never
    /// overlaps the menu bar (`visibleFrame`, not `frame`) — which is also what puts a `.top` bar
    /// directly beneath the menu bar with no special case.
    public static func frame(
        size: CGSize,
        in visibleFrame: CGRect,
        position: SidebarPosition,
        hidden: Bool
    ) -> CGRect {
        guard position.isVertical else {
            let width = min(size.width, visibleFrame.width - screenMargin * 2)
            let x = visibleFrame.midX - width / 2
            let visibleY: CGFloat = switch position {
            case .bottom: visibleFrame.minY + screenMargin
            default: visibleFrame.maxY - size.height - screenMargin
            }
            guard hidden else {
                return CGRect(x: x, y: visibleY, width: width, height: size.height)
            }
            // Hidden: park the panel just off the edge so revealing is a slide, not a pop.
            let hiddenY: CGFloat = switch position {
            case .bottom: visibleFrame.minY - size.height
            default: visibleFrame.maxY
            }
            return CGRect(x: x, y: hiddenY, width: width, height: size.height)
        }

        let height = min(size.height, visibleFrame.height - screenMargin * 2)
        let y = visibleFrame.midY - height / 2
        let visibleX: CGFloat = switch position {
        case .right: visibleFrame.maxX - size.width - screenMargin
        default: visibleFrame.minX + screenMargin
        }
        guard hidden else { return CGRect(x: visibleX, y: y, width: size.width, height: height) }

        let hiddenX: CGFloat = switch position {
        case .right: visibleFrame.maxX
        default: visibleFrame.minX - size.width
        }
        return CGRect(x: hiddenX, y: y, width: size.width, height: height)
    }

    /// Distance from the bar's leading edge — its top when vertical, its left when horizontal —
    /// to the centre of one row, so a flyout can be anchored to the item that opened it without a
    /// SwiftUI measurement round-trip.
    public static func rowCentre(
        sectionRowCounts: [Int],
        section: Int,
        row: Int,
        appearance: AppearanceConfiguration
    ) -> CGFloat {
        let sections = sectionRowCounts.filter { $0 > 0 }
        let rowSize = rowHeight(appearance)
        let spacing = CGFloat(appearance.iconSpacing)
        var offset = outerPadding

        for index in 0..<sections.count {
            if index == section {
                return offset + CGFloat(row) * (rowSize + spacing) + rowSize / 2
            }
            offset += CGFloat(sections[index]) * rowSize
                + CGFloat(max(0, sections[index] - 1)) * spacing
                + Design.separatorHeight + separatorSpacing * 2
        }
        return offset
    }

    /// Places a flyout beside the bar — to its side when vertical, above or below it when
    /// horizontal — anchored on `anchor` (a `rowCentre`) and clamped on screen.
    public static func flyoutFrame(
        size: CGSize,
        beside sidebar: CGRect,
        anchor: CGFloat,
        in visibleFrame: CGRect,
        position: SidebarPosition
    ) -> CGRect {
        guard position.isVertical else {
            let y: CGFloat = switch position {
            case .bottom: sidebar.maxY + screenMargin
            default: sidebar.minY - size.height - screenMargin
            }
            let unclampedX = sidebar.minX + anchor - size.width / 2
            return CGRect(
                x: clamp(unclampedX, size.width, visibleFrame.minX, visibleFrame.maxX),
                y: clamp(y, size.height, visibleFrame.minY, visibleFrame.maxY),
                width: size.width,
                height: size.height
            )
        }

        let x: CGFloat = switch position {
        case .right: sidebar.minX - size.width - screenMargin
        default: sidebar.maxX + screenMargin
        }
        // Panel coordinates grow upwards, the anchor is measured downwards from the bar's top.
        let anchorY = sidebar.maxY - anchor
        return CGRect(
            x: clamp(x, size.width, visibleFrame.minX, visibleFrame.maxX),
            y: clamp(anchorY - size.height / 2, size.height, visibleFrame.minY, visibleFrame.maxY),
            width: size.width,
            height: size.height
        )
    }

    public static func edgeTriggerFrame(
        in visibleFrame: CGRect,
        position: SidebarPosition
    ) -> CGRect {
        guard position.isVertical else {
            let y: CGFloat = switch position {
            case .bottom: visibleFrame.minY
            default: visibleFrame.maxY - edgeTriggerWidth
            }
            return CGRect(
                x: visibleFrame.minX,
                y: y,
                width: visibleFrame.width,
                height: edgeTriggerWidth
            )
        }

        let x: CGFloat = switch position {
        case .right: visibleFrame.maxX - edgeTriggerWidth
        default: visibleFrame.minX
        }
        return CGRect(x: x, y: visibleFrame.minY, width: edgeTriggerWidth, height: visibleFrame.height)
    }

    /// Keeps `origin` inside `[lower, upper]` once `length` is accounted for, leaving the screen
    /// margin clear at both ends.
    private static func clamp(
        _ origin: CGFloat,
        _ length: CGFloat,
        _ lower: CGFloat,
        _ upper: CGFloat
    ) -> CGFloat {
        min(max(origin, lower + screenMargin), upper - length - screenMargin)
    }
}
