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

    // MARK: - Zones

    /// How much of the bar each zone gets (M14). The head (the launcher) and the tail (now playing,
    /// Trash, Search) keep their rows whatever happens; only the middle scrolls, and each of its
    /// two sections scrolls inside its own extent rather than pushing the tail off the screen.
    public struct BarZones: Equatable, Sendable {
        /// Rows actually shown, which is the smaller of the section's count, its ceiling, and what
        /// the screen has room for.
        public var pinnedRows: Int
        public var runningRows: Int
        /// Extent along the bar's axis for each scrolling section.
        public var pinnedExtent: CGFloat
        public var runningExtent: CGFloat
        /// The whole bar, head and tail and separators included.
        public var total: CGFloat
        /// Application rows this edge of this screen can hold at all, once the head, the tail and
        /// the separators have taken theirs. What the bar grows into before anything scrolls.
        public var slots: Int
    }

    /// Rows the running section is never squeezed below while anything is running: a dock full of
    /// pins must not hide the fact that other applications are open.
    public static let runningFloor = 2

    /// Extent of one section, rows plus the gaps between them.
    public static func sectionExtent(rows: Int, appearance: AppearanceConfiguration) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * rowHeight(appearance)
            + CGFloat(rows - 1) * CGFloat(appearance.iconSpacing)
    }

    /// No display holds more rows than this. The cap exists so the conversion below cannot trap on
    /// an extent that is not a real screen — an infinite one, before the panel has been framed.
    public static let maximumRows = 1_000

    /// How many whole rows fit in `extent`. Half a row is worse than none: it reads as a clipped
    /// icon rather than as something to scroll.
    public static func rows(fitting extent: CGFloat, appearance: AppearanceConfiguration) -> Int {
        let row = rowHeight(appearance)
        let spacing = CGFloat(appearance.iconSpacing)
        guard extent >= row else { return 0 }
        let count = (extent + spacing) / (row + spacing)
        guard count < CGFloat(maximumRows) else { return maximumRows }
        return Int(count.rounded(.down))
    }

    private static var separatorExtent: CGFloat { Design.separatorHeight + separatorSpacing * 2 }

    /// `fixedRows` is one entry per section that cannot scroll — the launcher, and each part of the
    /// tail — because each of them costs a separator as well as its rows (D77).
    public static func zones(
        fixedRows: [Int],
        pinnedRows: Int,
        runningRows: Int,
        appearance: AppearanceConfiguration,
        available: CGFloat
    ) -> BarZones {
        let fixedSections = fixedRows.filter { $0 > 0 }
        let sectionsPresent = fixedSections.count
            + [pinnedRows, runningRows].filter { $0 > 0 }.count
        let fixed = outerPadding * 2
            + fixedSections.reduce(0) { $0 + sectionExtent(rows: $1, appearance: appearance) }
            + CGFloat(max(0, sectionsPresent - 1)) * separatorExtent
        let budget = max(0, available - fixed)

        // How many application rows this edge holds at all. Two sections cost slightly less than
        // one of the same total length — the gap between rows is smaller than the separator that
        // divides them — so counting as one section is the conservative answer.
        let slots = rows(fitting: budget, appearance: appearance)

        // Zero means "as many as fit": the bar grows into the screen it has, and a number is only
        // a ceiling on top of that.
        let pinnedCeiling = appearance.pinnedLimit > 0 ? min(appearance.pinnedLimit, slots) : slots
        let runningCeiling = appearance.runningLimit > 0 ? min(appearance.runningLimit, slots) : slots

        var pinned = min(pinnedRows, pinnedCeiling)
        var running = min(runningRows, runningCeiling)

        if pinned + running > slots {
            // Running keeps its floor first, then pinned takes what is left, then running takes
            // whatever pinned did not need.
            let floor = min(running, runningFloor)
            pinned = min(pinned, max(0, slots - floor))
            running = min(running, max(floor, slots - pinned))
        }

        let pinnedExtent = sectionExtent(rows: pinned, appearance: appearance)
        let runningExtent = sectionExtent(rows: running, appearance: appearance)
        return BarZones(
            pinnedRows: pinned,
            runningRows: running,
            pinnedExtent: pinnedExtent,
            runningExtent: runningExtent,
            total: min(available, fixed + pinnedExtent + runningExtent),
            slots: slots
        )
    }

    public static func size(
        zones: BarZones,
        appearance: AppearanceConfiguration,
        expanded: Bool
    ) -> CGSize {
        let thickness = width(appearance, expanded: expanded)
        return appearance.position.isVertical
            ? CGSize(width: thickness, height: zones.total)
            : CGSize(width: zones.total, height: thickness)
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

    // MARK: - Reserved space

    /// What is left of the screen once the bar has its strip — everything on the far side of it,
    /// measured from the edge the bar sits on. The 8 pt the bar keeps clear of the edge counts as
    /// the bar's: a window sliding into that gap still reads as being underneath it.
    public static func availableFrame(
        besides bar: CGRect,
        in visibleFrame: CGRect,
        position: SidebarPosition
    ) -> CGRect {
        switch position {
        case .left:
            let edge = min(max(visibleFrame.minX, bar.maxX), visibleFrame.maxX)
            return CGRect(
                x: edge,
                y: visibleFrame.minY,
                width: visibleFrame.maxX - edge,
                height: visibleFrame.height
            )
        case .right:
            let edge = max(min(visibleFrame.maxX, bar.minX), visibleFrame.minX)
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: edge - visibleFrame.minX,
                height: visibleFrame.height
            )
        case .bottom:
            let edge = min(max(visibleFrame.minY, bar.maxY), visibleFrame.maxY)
            return CGRect(
                x: visibleFrame.minX,
                y: edge,
                width: visibleFrame.width,
                height: visibleFrame.maxY - edge
            )
        case .top:
            let edge = max(min(visibleFrame.maxY, bar.minY), visibleFrame.minY)
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width,
                height: edge - visibleFrame.minY
            )
        }
    }

    /// The frame a window needs so it stops overlapping the bar, or `nil` for "leave it alone".
    /// It is pushed if it still fits in what is left, and resized only if it does not — a move is
    /// something the user can undo by dragging, a resize is not.
    ///
    /// Space-agnostic on purpose: every rectangle must be in the same coordinate space. The caller
    /// works in Accessibility coordinates, because that is the space it can read and write.
    public static func fit(_ window: CGRect, into available: CGRect, display: CGRect) -> CGRect? {
        guard available.width > 1, available.height > 1 else { return nil }
        // Windows belonging to another display, or straddling two, are that display's business.
        guard display.contains(CGPoint(x: window.midX, y: window.midY)) else { return nil }
        // Full screen — or the desktop — covers the display outright. Not ours to move, and the
        // bar hides over a full-screen space anyway.
        guard !window.insetBy(dx: -1, dy: -1).contains(display) else { return nil }
        guard !available.insetBy(dx: -0.5, dy: -0.5).contains(window) else { return nil }

        var frame = window
        frame.size.width = min(frame.width, available.width)
        frame.size.height = min(frame.height, available.height)
        frame.origin.x = min(max(frame.minX, available.minX), available.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, available.minY), available.maxY - frame.height)
        return frame == window ? nil : frame
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
