import CoreGraphics
import NexusCore
import Testing

@testable import NexusUI

@Suite("SidebarLayout")
struct SidebarLayoutTests {
    private let appearance: AppearanceConfiguration = {
        var appearance = AppearanceConfiguration()
        appearance.width = 64
        appearance.iconSize = 40
        appearance.iconSpacing = 8
        return appearance
    }()

    /// `#expect` rewrites its expression, which defeats Swift's implicit CGFloat/Double
    /// conversion — so every comparison here keeps both sides in CGFloat.
    private var spacing: CGFloat { CGFloat(appearance.iconSpacing) }

    @Test("Height grows by one row height plus one gap per extra row")
    func heightGrowsPerRow() {
        let one = SidebarLayout.height(sectionRowCounts: [1], appearance: appearance)
        let two = SidebarLayout.height(sectionRowCounts: [2], appearance: appearance)
        let expected: CGFloat = SidebarLayout.rowHeight(appearance) + spacing
        #expect(two - one == expected)
    }

    @Test("Separators are counted only between non-empty sections")
    func separators() {
        let merged = SidebarLayout.height(sectionRowCounts: [4], appearance: appearance)
        let split = SidebarLayout.height(sectionRowCounts: [2, 2], appearance: appearance)
        let separator = Design.separatorHeight + SidebarLayout.separatorSpacing * 2
        // Splitting swaps one within-section gap for one separator block.
        let delta: CGFloat = separator - spacing
        #expect(split - merged == delta)

        // Empty sections contribute neither rows nor separators.
        let twoRows = SidebarLayout.height(sectionRowCounts: [2, 0, 0], appearance: appearance)
        let expected: CGFloat = merged - (SidebarLayout.rowHeight(appearance) + spacing) * 2
        #expect(twoRows == expected)
    }

    @Test("An empty sidebar still has a visible height")
    func emptyHasHeight() {
        let height = SidebarLayout.height(sectionRowCounts: [0, 0], appearance: appearance)
        #expect(height == SidebarLayout.rowHeight(appearance) + SidebarLayout.outerPadding * 2)
    }

    @Test("Expanded width never shrinks below the configured width")
    func expandedWidth() {
        var wide = appearance
        wide.width = 300
        #expect(SidebarLayout.width(wide, expanded: true) == 300)
        #expect(SidebarLayout.width(appearance, expanded: true) == SidebarLayout.expandedWidth)
        #expect(SidebarLayout.width(appearance, expanded: false) == 64)
    }

    // MARK: - Frames

    private let visible = CGRect(x: 0, y: 0, width: 1_440, height: 875)

    @Test("Left placement sits inside the visible frame, vertically centred")
    func leftFrame() {
        let size = CGSize(width: 64, height: 400)
        let frame = SidebarLayout.frame(size: size, in: visible, position: .left, hidden: false)
        #expect(frame.minX == visible.minX + SidebarLayout.screenMargin)
        #expect(frame.midY == visible.midY)
        #expect(visible.contains(frame))
    }

    @Test("Right placement keeps the panel fully on screen")
    func rightFrame() {
        let size = CGSize(width: 64, height: 400)
        let frame = SidebarLayout.frame(size: size, in: visible, position: .right, hidden: false)
        #expect(frame.maxX == visible.maxX - SidebarLayout.screenMargin)
        #expect(visible.contains(frame))
    }

    @Test("A panel taller than the screen is clamped to the visible frame")
    func tallPanelClamped() {
        let size = CGSize(width: 64, height: 5_000)
        let frame = SidebarLayout.frame(size: size, in: visible, position: .left, hidden: false)
        #expect(frame.height == visible.height - SidebarLayout.screenMargin * 2)
        #expect(visible.contains(frame))
    }

    @Test("Hidden parks the panel entirely off the configured edge")
    func hiddenFrame() {
        let size = CGSize(width: 64, height: 400)
        let left = SidebarLayout.frame(size: size, in: visible, position: .left, hidden: true)
        #expect(left.maxX <= visible.minX)
        let right = SidebarLayout.frame(size: size, in: visible, position: .right, hidden: true)
        #expect(right.minX >= visible.maxX)
    }

    @Test("The edge trigger is a full-height strip on the configured edge")
    func edgeTrigger() {
        let left = SidebarLayout.edgeTriggerFrame(in: visible, position: .left)
        #expect(left.minX == visible.minX)
        #expect(left.width == SidebarLayout.edgeTriggerWidth)
        #expect(left.height == visible.height)

        let right = SidebarLayout.edgeTriggerFrame(in: visible, position: .right)
        #expect(right.maxX == visible.maxX)
    }

    @Test("Placement works on a secondary display with a negative origin")
    func secondaryDisplay() {
        let secondary = CGRect(x: -1_920, y: 200, width: 1_920, height: 1_080)
        let frame = SidebarLayout.frame(
            size: CGSize(width: 64, height: 400),
            in: secondary,
            position: .left,
            hidden: false
        )
        #expect(secondary.contains(frame))
    }

    // MARK: - Horizontal edges

    @Test("A horizontal bar swaps the axes: rows run along its width")
    func horizontalSize() {
        var horizontal = appearance
        horizontal.position = .bottom
        let vertical = SidebarLayout.size(sectionRowCounts: [3, 2], appearance: appearance, expanded: false)
        let flat = SidebarLayout.size(sectionRowCounts: [3, 2], appearance: horizontal, expanded: false)
        #expect(flat.width == vertical.height)
        // Not the vertical bar's width: a horizontal bar's thickness has to hold the icon, its
        // padding and the running dot underneath it (D102).
        #expect(flat.height == CGFloat(horizontal.iconSize) + SidebarLayout.horizontalExtras)
        #expect(flat.height > vertical.width)
    }

    @Test("A horizontal bar is never thinner than its icons need")
    func horizontalThickness() {
        var horizontal = appearance
        horizontal.position = .bottom
        horizontal.iconSize = 64
        horizontal.width = 64
        let thickness = SidebarLayout.width(horizontal, expanded: false)
        #expect(thickness >= CGFloat(horizontal.iconSize) + Design.runningDotDiameter)
        #expect(thickness == 64 + SidebarLayout.horizontalExtras)

        // A configured width larger than the icons need is still honoured.
        horizontal.width = 200
        #expect(SidebarLayout.width(horizontal, expanded: false) == 200)
    }

    @Test("Hover-expand is ignored on a horizontal bar")
    func horizontalNeverExpands() {
        var horizontal = appearance
        horizontal.position = .top
        #expect(
            SidebarLayout.width(horizontal, expanded: true)
                == SidebarLayout.width(horizontal, expanded: false)
        )
        #expect(SidebarLayout.width(appearance, expanded: true) == SidebarLayout.expandedWidth)
    }

    @Test("Bottom placement sits on the bottom edge, horizontally centred")
    func bottomFrame() {
        let size = CGSize(width: 400, height: 64)
        let frame = SidebarLayout.frame(size: size, in: visible, position: .bottom, hidden: false)
        #expect(frame.minY == visible.minY + SidebarLayout.screenMargin)
        #expect(frame.midX == visible.midX)
        #expect(visible.contains(frame))
    }

    /// `visibleFrame` already excludes the menu bar, which is the whole reason a `.top` bar needs
    /// no special case — and the one place where using `frame` instead would look almost right.
    @Test("Top placement clears the menu bar")
    func topFrame() {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let belowMenuBar = CGRect(x: 0, y: 0, width: 1_440, height: 875)
        let size = CGSize(width: 400, height: 64)
        let frame = SidebarLayout.frame(size: size, in: belowMenuBar, position: .top, hidden: false)
        #expect(frame.maxY == belowMenuBar.maxY - SidebarLayout.screenMargin)
        #expect(frame.maxY < screen.maxY)
        #expect(belowMenuBar.contains(frame))
    }

    @Test("A bar wider than the screen is clamped to the visible frame")
    func wideBarClamped() {
        let size = CGSize(width: 5_000, height: 64)
        let frame = SidebarLayout.frame(size: size, in: visible, position: .bottom, hidden: false)
        #expect(frame.width == visible.width - SidebarLayout.screenMargin * 2)
        #expect(visible.contains(frame))
    }

    @Test("Hidden parks a horizontal bar off its own edge")
    func hiddenHorizontal() {
        let size = CGSize(width: 400, height: 64)
        let bottom = SidebarLayout.frame(size: size, in: visible, position: .bottom, hidden: true)
        #expect(bottom.maxY <= visible.minY)
        let top = SidebarLayout.frame(size: size, in: visible, position: .top, hidden: true)
        #expect(top.minY >= visible.maxY)
    }

    @Test("The edge trigger is a full-width strip on a horizontal edge")
    func horizontalEdgeTrigger() {
        let bottom = SidebarLayout.edgeTriggerFrame(in: visible, position: .bottom)
        #expect(bottom.minY == visible.minY)
        #expect(bottom.height == SidebarLayout.edgeTriggerWidth)
        #expect(bottom.width == visible.width)

        let top = SidebarLayout.edgeTriggerFrame(in: visible, position: .top)
        #expect(top.maxY == visible.maxY)
    }

    @Test("A flyout for a horizontal bar sits above it, centred on the row")
    func horizontalFlyout() {
        let bar = CGRect(x: 500, y: 8, width: 400, height: 64)
        let size = CGSize(width: 320, height: 200)
        let anchor: CGFloat = 100
        let frame = SidebarLayout.flyoutFrame(
            size: size, beside: bar, anchor: anchor, in: visible, position: .bottom
        )
        #expect(frame.minY == bar.maxY + SidebarLayout.screenMargin)
        #expect(frame.midX == bar.minX + anchor)
        #expect(visible.contains(frame))

        let above = SidebarLayout.flyoutFrame(
            size: size,
            beside: CGRect(x: 500, y: visible.maxY - 72, width: 400, height: 64),
            anchor: anchor,
            in: visible,
            position: .top
        )
        #expect(above.maxY <= visible.maxY - SidebarLayout.screenMargin)
    }

    @Test("A flyout near the end of a horizontal bar stays on screen")
    func horizontalFlyoutClamped() {
        let bar = CGRect(x: 8, y: 8, width: 1_424, height: 64)
        let size = CGSize(width: 320, height: 200)
        let frame = SidebarLayout.flyoutFrame(
            size: size, beside: bar, anchor: 1_400, in: visible, position: .bottom
        )
        #expect(frame.maxX <= visible.maxX - SidebarLayout.screenMargin)
        #expect(visible.contains(frame))
    }
}
