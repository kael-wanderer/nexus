import Foundation
import NexusCore
import Testing

@testable import NexusUI

@Suite("Design")
struct DesignTests {
    @Test("Reduce Motion suppresses animation at the call site")
    func reduceMotion() {
        #expect(Design.animation(Design.reveal, reduceMotion: true) == nil)
        #expect(Design.animation(Design.reveal, reduceMotion: false) != nil)
    }

    /// The badge must never hang over the edge of the row it decorates: outside the row is outside
    /// the row's hover region, and that is what made it flash (D110).
    @Test("The remove badge always lands wholly inside the row")
    func removeBadgeStaysInside() {
        let diameter = Design.removeBadgeDiameter
        let cases: [(CGRect, CGSize)] = [
            // A popover tile: a 36 pt icon centred in 76 pt, five points down from the top.
            (CGRect(x: 20, y: 5, width: 36, height: 36), CGSize(width: 76, height: 76)),
            // A row of an expanded vertical bar: the icon at the leading edge.
            (CGRect(x: 4, y: 4, width: 64, height: 64), CGSize(width: 200, height: 72)),
            // A row of a horizontal bar, and a corner case: the icon fills the row exactly.
            (CGRect(x: 4, y: 4, width: 64, height: 64), CGSize(width: 72, height: 72)),
            (CGRect(x: 0, y: 0, width: 12, height: 12), CGSize(width: 12, height: 12)),
        ]
        for (icon, size) in cases {
            let centre = Design.removeBadgeCentre(icon: icon, in: size)
            let badge = CGRect(
                x: centre.x - diameter / 2,
                y: centre.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            #expect(badge.minX >= 0)
            #expect(badge.minY >= 0)
            #expect(badge.maxX <= max(size.width, diameter))
            #expect(badge.maxY <= max(size.height, diameter))
        }

        // Where there is room, it stays on the icon's corner rather than being moved for no reason.
        let roomy = Design.removeBadgeCentre(
            icon: CGRect(x: 30, y: 30, width: 36, height: 36),
            in: CGSize(width: 120, height: 120)
        )
        #expect(roomy == CGPoint(x: 30, y: 30))
    }
}

@Suite("Flyout sizes")
struct FlyoutSizeTests {
    @Test("Every metric grows from small to medium to large")
    func monotonic() {
        let sizes: [FlyoutSize] = [.small, .medium, .large]
        let cardWidths = sizes.map(\.cardSize.width)
        let cardHeights = sizes.map(\.cardSize.height)
        let artworkSizes = sizes.map(\.artworkSize)
        let tileWidths = sizes.map(\.tileSize.width)
        let tileHeights = sizes.map(\.tileSize.height)

        #expect(cardWidths == cardWidths.sorted())
        #expect(cardHeights == cardHeights.sorted())
        #expect(artworkSizes == artworkSizes.sorted())
        #expect(tileWidths == tileWidths.sorted())
        #expect(tileHeights == tileHeights.sorted())
        // Strictly increasing, not just non-decreasing: three sizes that drew the same thing would
        // not be a setting.
        #expect(Set(cardWidths).count == 3)
        #expect(Set(cardHeights).count == 3)
        #expect(Set(artworkSizes).count == 3)
        #expect(Set(tileWidths).count == 3)
        #expect(Set(tileHeights).count == 3)
    }

    @Test("Medium matches the reference screenshot's measurements")
    func mediumIsTheReference() {
        #expect(FlyoutSize.medium.cardSize == CGSize(width: 340, height: 210))
        #expect(FlyoutSize.medium.artworkSize == 190)
        #expect(FlyoutSize.medium.tileSize == CGSize(width: 96, height: 48))
    }
}

@Suite("Shortcuts pane")
struct ShortcutsPaneTests {
    @Test("Two slots holding the same combination is reported")
    func shortcutConflictIsFound() {
        var configuration = NexusConfiguration()
        configuration.search.shortcut = .optionSpace
        configuration.general.focusBarShortcut = .optionSpace

        #expect(ShortcutsPane.conflicts(in: configuration).contains(.optionSpace))
    }

    @Test("Distinct combinations conflict with nothing")
    func noConflictWhenDistinct() {
        var configuration = NexusConfiguration()
        configuration.search.shortcut = .optionSpace
        configuration.general.focusBarShortcut = .focusBarDefault
        configuration.general.windowSwitcherShortcut = .windowSwitcherDefault

        #expect(ShortcutsPane.conflicts(in: configuration).isEmpty)
    }
}
