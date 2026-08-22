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
}
