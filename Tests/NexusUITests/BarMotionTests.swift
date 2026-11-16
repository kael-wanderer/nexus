import CoreGraphics
import NexusCore
import SwiftUI
import Testing

@testable import NexusUI

@Suite("Bar motion")
struct BarMotionTests {
    @Test("Thickness follows the expanded state, never below the configured width")
    func thickness() {
        var a = AppearanceConfiguration(); a.position = .left; a.width = 64
        #expect(BarMotion.resolve(appearance: a, expanded: false, hidden: false).thickness == 64)
        #expect(BarMotion.resolve(appearance: a, expanded: true, hidden: false).thickness == 220)
        a.width = 260
        #expect(BarMotion.resolve(appearance: a, expanded: true, hidden: false).thickness == 260)
    }

    @Test("A horizontal bar never expands (D53)", arguments: [SidebarPosition.top, .bottom])
    func horizontalNeverExpands(position: SidebarPosition) {
        // A small icon, so the horizontal bar's computed thickness is the configured width.
        var a = AppearanceConfiguration(); a.position = position; a.width = 64; a.iconSize = 24
        #expect(BarMotion.resolve(appearance: a, expanded: true, hidden: false).thickness == 64)
        #expect(BarMotion.resolve(appearance: a, expanded: false, hidden: false).thickness == 64)
    }

    @Test("The bar is drawn exactly as thick as its window is", arguments: SidebarPosition.allCases)
    func matchesTheWindow(position: SidebarPosition) {
        var a = AppearanceConfiguration(); a.position = position
        for expanded in [false, true] {
            #expect(
                BarMotion.resolve(appearance: a, expanded: expanded, hidden: false).thickness
                    == SidebarLayout.width(a, expanded: expanded)
            )
        }
    }

    @Test("A hidden bar is pushed off its own edge by its thickness plus the margin",
          arguments: [(SidebarPosition.left, CGSize(width: -72, height: 0), Alignment.leading),
                      (.right, CGSize(width: 72, height: 0), .trailing),
                      (.top, CGSize(width: 0, height: -72), .top),
                      (.bottom, CGSize(width: 0, height: 72), .bottom)])
    func hiddenOffset(position: SidebarPosition, offset: CGSize, alignment: Alignment) {
        var a = AppearanceConfiguration(); a.position = position; a.width = 64; a.iconSize = 24
        let hidden = BarMotion.resolve(appearance: a, expanded: false, hidden: true)
        #expect(hidden.offset == offset)                 // 64 + SidebarLayout.screenMargin (8)
        #expect(hidden.alignment == alignment)
        #expect(BarMotion.resolve(appearance: a, expanded: false, hidden: false).offset == .zero)
    }

    @Test("The window is wide for the whole of any transition that touches the expanded state")
    func windowSize() {
        #expect(BarMotion.windowExpanded(from: false, to: true))
        #expect(BarMotion.windowExpanded(from: true, to: false))
        #expect(BarMotion.windowExpanded(from: true, to: true))
        #expect(!BarMotion.windowExpanded(from: false, to: false))
    }
}
