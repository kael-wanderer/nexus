import Foundation
import Testing

@testable import NexusCore

@Suite("SpotlightShortcut")
struct SpotlightShortcutTests {
    @Test("An enabled Spotlight hotkey is reported as enabled")
    func enabled() {
        let defaults: [String: Any] = ["64": ["enabled": true, "value": [:]]]
        #expect(SpotlightShortcut.state(in: defaults) == .enabled)
    }

    @Test("A disabled Spotlight hotkey is reported as disabled")
    func disabled() {
        let defaults: [String: Any] = ["64": ["enabled": false, "value": [:]]]
        #expect(SpotlightShortcut.state(in: defaults) == .disabled)
    }

    @Test("Anything unexpected reads as unknown, so the guide falls back to static text")
    func unknown() {
        #expect(SpotlightShortcut.state(in: nil) == .unknown)
        #expect(SpotlightShortcut.state(in: [:]) == .unknown)
        #expect(SpotlightShortcut.state(in: ["64": "nonsense"]) == .unknown)
        #expect(SpotlightShortcut.state(in: ["64": ["value": [:]]]) == .unknown)
        #expect(SpotlightShortcut.state(in: ["65": ["enabled": false]]) == .unknown)
    }

    @Test("Reading the live domain never throws and returns a defined state")
    func liveRead() {
        let state = SpotlightShortcut.state()
        #expect([.enabled, .disabled, .unknown].contains(state))
    }
}

@Suite("KeyboardShortcut display")
struct KeyboardShortcutDisplayTests {
    @Test("Modifier symbols appear in the macOS order")
    func modifierOrder() {
        let all = KeyboardShortcut(
            keyCode: KeyboardShortcut.spaceKeyCode,
            modifiers: KeyboardShortcut.controlKey | KeyboardShortcut.optionKey
                | KeyboardShortcut.shiftKey | KeyboardShortcut.cmdKey
        )
        #expect(all.displayString == "⌃⌥⇧⌘Space")
    }

    @Test("The defaults render as expected")
    func defaults() {
        #expect(KeyboardShortcut.optionSpace.displayString == "⌥Space")
        #expect(KeyboardShortcut.commandSpace.displayString == "⌘Space")
    }

    @Test("NSEvent modifier flags convert to Carbon masks")
    func carbonConversion() {
        #expect(KeyboardShortcut.carbonModifiers(from: [.command]) == KeyboardShortcut.cmdKey)
        #expect(KeyboardShortcut.carbonModifiers(from: [.option]) == KeyboardShortcut.optionKey)
        #expect(KeyboardShortcut.carbonModifiers(from: [.control]) == KeyboardShortcut.controlKey)
        #expect(KeyboardShortcut.carbonModifiers(from: [.shift]) == KeyboardShortcut.shiftKey)
        #expect(
            KeyboardShortcut.carbonModifiers(from: [.command, .shift])
                == KeyboardShortcut.cmdKey | KeyboardShortcut.shiftKey
        )
        #expect(KeyboardShortcut.carbonModifiers(from: [.capsLock, .function]) == 0)
    }

    @Test("A letter key renders as that letter")
    func letterKey() {
        // 0 is kVK_ANSI_A on every ANSI layout.
        #expect(KeyboardShortcut(keyCode: 0, modifiers: KeyboardShortcut.optionKey).displayString == "⌥A")
    }
}
