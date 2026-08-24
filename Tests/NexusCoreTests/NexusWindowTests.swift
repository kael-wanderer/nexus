import Foundation
import Testing

@testable import NexusCore

@Suite("NexusWindow")
struct NexusWindowTests {
    private func window(title: String) -> NexusWindow {
        NexusWindow(
            identity: WindowIdentity(owner: ApplicationIdentity(bundleIdentifier: "com.apple.Safari"), number: 1),
            title: title
        )
    }

    @Test("A window with a title shows it")
    func titled() {
        #expect(window(title: "GitHub").displayTitle == "GitHub")
    }

    @Test("An untitled window still shows something readable")
    func untitled() {
        #expect(window(title: "").displayTitle == "Untitled window")
    }
}
