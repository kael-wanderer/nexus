import CoreGraphics
import NexusCore

/// Panel geometry derived from configuration and item counts. Pure, so the panel frame is known
/// without a SwiftUI measurement round-trip — and so it can be unit-tested.
public enum SidebarLayout {
    public static let outerPadding: CGFloat = 8
    public static let expandedWidth: CGFloat = 220
    public static let separatorSpacing: CGFloat = 6
    public static let screenMargin: CGFloat = 8
    public static let edgeTriggerWidth: CGFloat = 2

    public static func rowHeight(_ appearance: AppearanceConfiguration) -> CGFloat {
        appearance.iconSize + 8
    }

    public static func width(_ appearance: AppearanceConfiguration, expanded: Bool) -> CGFloat {
        expanded ? max(expandedWidth, appearance.width) : appearance.width
    }

    /// `sectionRowCounts` lists the rows in each visible section, in order. Empty sections must
    /// not be passed in — separators are drawn between the sections that are actually there.
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
        CGSize(
            width: width(appearance, expanded: expanded),
            height: height(sectionRowCounts: sectionRowCounts, appearance: appearance)
        )
    }

    /// Frame on the given visible area, clamped so the panel never runs off screen and never
    /// overlaps the menu bar (`visibleFrame`, not `frame`).
    public static func frame(
        size: CGSize,
        in visibleFrame: CGRect,
        position: SidebarPosition,
        hidden: Bool
    ) -> CGRect {
        let height = min(size.height, visibleFrame.height - screenMargin * 2)
        let y = visibleFrame.midY - height / 2
        let visibleX: CGFloat = switch position {
        case .left: visibleFrame.minX + screenMargin
        case .right: visibleFrame.maxX - size.width - screenMargin
        }
        guard hidden else { return CGRect(x: visibleX, y: y, width: size.width, height: height) }

        // Hidden: park the panel just off the edge so revealing is a slide, not a pop.
        let hiddenX: CGFloat = switch position {
        case .left: visibleFrame.minX - size.width
        case .right: visibleFrame.maxX
        }
        return CGRect(x: hiddenX, y: y, width: size.width, height: height)
    }

    /// Distance from the top of the panel to the centre of one row, so a flyout can be anchored
    /// to the item that opened it without a SwiftUI measurement round-trip.
    public static func rowCentreFromTop(
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

    /// Places a flyout beside the sidebar, anchored on `anchorFromTop` and clamped on screen.
    public static func flyoutFrame(
        size: CGSize,
        beside sidebar: CGRect,
        anchorFromTop: CGFloat,
        in visibleFrame: CGRect,
        position: SidebarPosition
    ) -> CGRect {
        let x: CGFloat = switch position {
        case .left: sidebar.maxX + screenMargin
        case .right: sidebar.minX - size.width - screenMargin
        }
        let anchorY = sidebar.maxY - anchorFromTop
        let unclampedY = anchorY - size.height / 2
        let y = min(
            max(unclampedY, visibleFrame.minY + screenMargin),
            visibleFrame.maxY - size.height - screenMargin
        )
        let clampedX = min(
            max(x, visibleFrame.minX + screenMargin),
            visibleFrame.maxX - size.width - screenMargin
        )
        return CGRect(x: clampedX, y: y, width: size.width, height: size.height)
    }

    public static func edgeTriggerFrame(
        in visibleFrame: CGRect,
        position: SidebarPosition
    ) -> CGRect {
        let x: CGFloat = switch position {
        case .left: visibleFrame.minX
        case .right: visibleFrame.maxX - edgeTriggerWidth
        }
        return CGRect(x: x, y: visibleFrame.minY, width: edgeTriggerWidth, height: visibleFrame.height)
    }
}
