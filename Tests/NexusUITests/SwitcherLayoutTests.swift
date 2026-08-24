import CoreGraphics
import Testing

@testable import NexusUI

@Suite("Switcher layout")
struct SwitcherLayoutTests {
    @Test("Columns fill the width and never drop below one")
    func columns() {
        #expect(SwitcherLayout.columns(forWidth: 1600, cardWidth: 320, spacing: 20) == 4)
        #expect(SwitcherLayout.columns(forWidth: 700, cardWidth: 320, spacing: 20) == 2)
        #expect(SwitcherLayout.columns(forWidth: 100, cardWidth: 320, spacing: 20) == 1)
        #expect(SwitcherLayout.columns(forWidth: 0, cardWidth: 320, spacing: 20) == 1)
    }

    @Test("A card is wider than it is tall, in the proportions of a screen")
    func cardShape() {
        #expect(SwitcherLayout.cardWidth > SwitcherLayout.cardHeight)
    }
}
