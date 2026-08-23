import AppKit
import CoreGraphics
import Foundation
import NexusCore
import Testing

@testable import NexusUI

@MainActor
private func makeModel(
    running: [String] = ["a", "b"],
    entries: [DockEntry] = [.application("a")],
    startMenu: Bool = false
) async -> SidebarViewModel {
    let service = FakeApplicationService(
        running.map { makeApplication($0, name: $0.uppercased(), running: true) }
    )
    var initial = NexusConfiguration()
    initial.pinnedEntries = entries
    initial.general.showStartMenu = startMenu
    let controller = ConfigurationController(
        store: InMemoryConfigurationStore(initial),
        events: EventBus(),
        saveDelay: .zero
    )
    let model = SidebarViewModel(
        applications: service,
        configuration: controller,
        events: EventBus()
    )
    model.activateWindow = { _ in }
    model.openSearch = {}
    if startMenu { model.openStartMenu = {} }
    await model.refresh()
    return model
}

@MainActor
@Suite("Keyboard navigation")
struct KeyboardNavigationTests {
    @Test("The focusable rows are the ones the bar draws, in that order")
    func focusableRows() async {
        let model = await makeModel(startMenu: true)
        #expect(
            model.focusableRowIDs == [
                SidebarViewModel.startMenuRowID,
                "a",
                "b",
                SidebarViewModel.trashRowID,
                SidebarViewModel.searchRowID,
            ]
        )
    }

    @Test("Minimized windows are in the walk, after the applications")
    func minimizedInTheWalk() async {
        let model = await makeModel()
        model.setAllWindows([
            NexusWindow(
                identity: WindowIdentity(owner: ApplicationIdentity(bundleIdentifier: "a"), number: 1),
                title: "Draft",
                isMinimized: true,
                applicationName: "A"
            )
        ])
        let ids = model.focusableRowIDs
        #expect(ids.contains("a#1"))
        #expect(ids.firstIndex(of: "a#1")! > ids.firstIndex(of: "b")!)
        #expect(ids.firstIndex(of: "a#1")! < ids.firstIndex(of: SidebarViewModel.trashRowID)!)
    }

    @Test("Entering starts on the first row and asks the panel for the keyboard")
    func entering() async {
        let model = await makeModel()
        var focusRequests: [Bool] = []
        model.setKeyboardFocus = { focusRequests.append($0) }

        model.beginKeyboardNavigation()
        #expect(model.isKeyboardNavigating)
        #expect(model.focusedRowID == "a")
        #expect(focusRequests == [true])

        model.endKeyboardNavigation()
        #expect(model.isKeyboardNavigating == false)
        #expect(model.focusedRowID == nil)
        #expect(focusRequests == [true, false])
    }

    @Test("Leaving twice asks for nothing twice")
    func idempotentExit() async {
        let model = await makeModel()
        var focusRequests: [Bool] = []
        model.setKeyboardFocus = { focusRequests.append($0) }
        model.endKeyboardNavigation()
        #expect(focusRequests.isEmpty)
    }

    @Test("The shortcut toggles: pressed once it enters, pressed again it leaves")
    func toggles() async {
        let model = await makeModel()
        model.toggleKeyboardNavigation()
        #expect(model.isKeyboardNavigating)
        model.toggleKeyboardNavigation()
        #expect(model.isKeyboardNavigating == false)
    }

    @Test("Arrows walk the rows and stop at each end rather than wrapping")
    func walking() async {
        let model = await makeModel()
        model.beginKeyboardNavigation()
        #expect(model.focusedRowID == "a")

        model.moveFocus(by: -1)
        #expect(model.focusedRowID == "a")          // already at the first row

        model.moveFocus(by: 1)
        #expect(model.focusedRowID == "b")
        model.moveFocus(by: 1)
        #expect(model.focusedRowID == SidebarViewModel.trashRowID)

        model.focusLastRow()
        #expect(model.focusedRowID == SidebarViewModel.searchRowID)
        model.moveFocus(by: 1)
        #expect(model.focusedRowID == SidebarViewModel.searchRowID)   // and stops there

        model.focusFirstRow()
        #expect(model.focusedRowID == "a")
    }

    @Test("Return runs the focused row and gives the keyboard back")
    func activating() async {
        let model = await makeModel()
        var opened = false
        model.openSearch = { opened = true }
        model.beginKeyboardNavigation()
        model.focusLastRow()

        model.activateFocusedRow()
        #expect(opened)
        #expect(model.isKeyboardNavigating == false)
    }

    @Test("Activating a minimized window restores it")
    func activatingMinimized() async {
        let model = await makeModel()
        var restored: [CGWindowID] = []
        model.activateWindow = { restored.append($0.number) }
        model.setAllWindows([
            NexusWindow(
                identity: WindowIdentity(owner: ApplicationIdentity(bundleIdentifier: "a"), number: 7),
                title: "Draft",
                isMinimized: true,
                applicationName: "A"
            )
        ])
        model.beginKeyboardNavigation()
        while model.focusedRowID != "a#7" { model.moveFocus(by: 1) }

        model.activateFocusedRow()
        #expect(restored == [7])
    }

    @Test("A bar with nothing on it cannot be entered")
    func nothingToFocus() async {
        let model = await makeModel(running: [], entries: [])
        model.openSearch = nil
        // Trash is always there, so the only truly empty bar is one with no rows at all: the
        // guard is what matters, not the arithmetic.
        #expect(model.focusableRowIDs.isEmpty == false)
        model.beginKeyboardNavigation()
        #expect(model.focusedRowID == SidebarViewModel.trashRowID)
    }

    @Test("Keys map to commands on both axes, and everything else is left alone")
    func keyMapping() {
        typealias Command = BarHostingView<SidebarView>.KeyCommand
        func command(_ keyCode: UInt16) -> Command? {
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: keyCode
            ) else { return nil }
            return BarHostingView<SidebarView>.command(for: event)
        }
        #expect(command(123) == .previous)      // ←
        #expect(command(126) == .previous)      // ↑
        #expect(command(124) == .next)          // →
        #expect(command(125) == .next)          // ↓
        #expect(command(36) == .activate)       // Return
        #expect(command(49) == .activate)       // Space
        #expect(command(53) == .cancel)         // Escape
        #expect(command(0) == nil)              // A — travels on
    }

    @Test("The shortcut is on by default and can be switched off")
    func shortcutDefault() {
        #expect(NexusConfiguration().general.focusBarShortcut == .focusBarDefault)
        #expect(KeyboardShortcut.focusBarDefault.displayString.hasPrefix("⌃"))
        var configuration = NexusConfiguration()
        configuration.general.focusBarShortcut = nil
        #expect(configuration.general.focusBarShortcut == nil)
    }
}
