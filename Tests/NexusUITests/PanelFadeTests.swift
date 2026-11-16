import AppKit
import Testing

@testable import NexusUI

@MainActor
@Suite("Popover fade")
struct PanelFadeTests {
    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 100, y: 100, width: 120, height: 80),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        return panel
    }

    @Test("Show then hide leaves the panel off screen")
    func showThenHide() async throws {
        let fade = PanelFade(reduceMotion: { false })
        let panel = makePanel()
        fade.show(panel)
        #expect(panel.isVisible)
        fade.hide(panel)
        try await waitUntil { !panel.isVisible }
        #expect(!panel.isVisible)
        try await waitUntil { panel.alphaValue == 1 }
        #expect(panel.alphaValue == 1)
    }

    @Test("Hide then show at once leaves the panel on screen")
    func hideThenShow() async throws {
        let fade = PanelFade(reduceMotion: { false })
        let panel = makePanel()
        fade.show(panel)
        fade.hide(panel)
        fade.show(panel)
        // Showing that nothing removes the panel after the old hide's fade would have ended.
        try await Task.sleep(for: .milliseconds(200))
        #expect(panel.isVisible)
        // The fade back in is an event that will finish, so it is waited for, not guessed at.
        try await waitUntil { panel.alphaValue == 1 }
        #expect(panel.isVisible)
        #expect(panel.alphaValue == 1)
        fade.hide(panel)
        try await waitUntil { !panel.isVisible }
    }

    @Test("Reduce motion shows and hides synchronously")
    func reduceMotion() {
        let fade = PanelFade(reduceMotion: { true })
        let panel = makePanel()
        fade.show(panel)
        #expect(panel.isVisible)
        #expect(panel.alphaValue == 1)
        fade.hide(panel)
        #expect(!panel.isVisible)
        #expect(panel.alphaValue == 1)
    }
}
