import CoreGraphics
import Testing

@testable import NexusUI

@Suite("Switcher panel")
struct SwitcherPanelTests {
    @Test("The panel fills the visible area of its screen")
    func fillsTheScreen() {
        let visible = CGRect(x: 0, y: 0, width: 2560, height: 1410)
        #expect(SwitcherPanelController.frame(for: visible) == visible)
    }

    @Test("A screen with an origin away from zero is respected")
    func secondDisplay() {
        let visible = CGRect(x: 2560, y: 0, width: 2560, height: 1440)
        #expect(SwitcherPanelController.frame(for: visible) == visible)
    }
}
