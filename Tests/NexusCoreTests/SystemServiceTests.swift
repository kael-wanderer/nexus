import ApplicationServices
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

@Suite("LoginItemService")
@MainActor
struct LoginItemLocationTests {
    @Test("An app in /Applications is in its install location")
    func applications() {
        #expect(LoginItemService.isInstallLocation(URL(fileURLWithPath: "/Applications/Nexus.app")))
    }

    @Test("A build directory is not")
    func buildDirectory() {
        #expect(
            LoginItemService.isInstallLocation(
                URL(fileURLWithPath: "/Users/someone/code/Nexus/build/Nexus.app")
            ) == false
        )
    }

    @Test("Nor is a subfolder of Applications, which login items would not survive tidying")
    func nested() {
        #expect(
            LoginItemService.isInstallLocation(
                URL(fileURLWithPath: "/Applications/Utilities/Nexus.app")
            ) == false
        )
    }

    @Test("The user's own Applications folder counts")
    func userDomain() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(
            LoginItemService.isInstallLocation(
                home.appendingPathComponent("Applications/Nexus.app")
            )
        )
    }
}

@Suite("HotKeyService slots")
struct HotKeySlotTests {
    @Test("Every hotkey slot has its own Carbon identifier")
    func slotsAreDistinct() {
        let identifiers = HotKeyService.Slot.allCases.map(\.rawValue)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(HotKeyService.Slot.allCases.contains(.windowSwitcher))
    }
}

@Suite("Which windows count as windows")
struct WindowSubroleTests {
    @Test("A standard window counts, minimized or not")
    func standardWindows() {
        #expect(WindowService.isListable(subrole: kAXStandardWindowSubrole, minimized: false))
        #expect(WindowService.isListable(subrole: kAXStandardWindowSubrole, minimized: true))
    }

    /// The bug: minimising a window changes its subrole — Finder's becomes `AXDialog` — so a
    /// filter on `AXStandardWindow` alone lost it, and the minimized section stayed empty (D100).
    @Test("A minimized window counts even after its subrole changes")
    func minimizedDialog() {
        #expect(WindowService.isListable(subrole: kAXDialogSubrole, minimized: true))
        #expect(WindowService.isListable(subrole: nil, minimized: true))
    }

    @Test("Sheets, palettes and the desktop still do not count")
    func nonWindows() {
        #expect(WindowService.isListable(subrole: kAXDialogSubrole, minimized: false) == false)
        #expect(WindowService.isListable(subrole: nil, minimized: false) == false)
        #expect(WindowService.isListable(subrole: kAXUnknownSubrole, minimized: false) == false)
        // Even minimized, an AXUnknown element is not a window anybody asked for.
        #expect(WindowService.isListable(subrole: kAXUnknownSubrole, minimized: true) == false)
    }
}

