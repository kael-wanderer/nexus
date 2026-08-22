import AppKit
import NexusCore

/// The menu-bar status item — the only chrome an `LSUIElement` app has.
@MainActor
final class StatusItemController {
    struct Actions {
        var toggleSidebar: (() -> Void)?
        var openSettings: (() -> Void)?
        var runSetupAgain: (() -> Void)?
        var openSearch: (() -> Void)?
    }

    private var statusItem: NSStatusItem?
    private var actions: Actions

    init(actions: Actions) {
        self.actions = actions
    }

    var isVisible: Bool { statusItem != nil }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        if visible { install() } else { remove() }
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "square.grid.2x2",
            accessibilityDescription: String(localized: "Nexus")
        )
        item.button?.image?.isTemplate = true
        item.button?.setAccessibilityLabel(String(localized: "Nexus"))
        item.menu = buildMenu()
        statusItem = item
        Log.app.debug("Status item installed")
    }

    private func remove() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        Log.app.debug("Status item removed")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        if actions.openSearch != nil {
            menu.addItem(actionItem(String(localized: "Search…"), #selector(openSearch), ""))
        }
        if actions.toggleSidebar != nil {
            menu.addItem(actionItem(String(localized: "Toggle Sidebar"), #selector(toggleSidebar), ""))
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        if actions.openSettings != nil {
            menu.addItem(actionItem(String(localized: "Settings…"), #selector(openSettings), ","))
        }
        if actions.runSetupAgain != nil {
            menu.addItem(actionItem(String(localized: "Run Setup Again…"), #selector(runSetupAgain), ""))
        }
        menu.addItem(.separator())
        menu.addItem(actionItem(String(localized: "Quit Nexus"), #selector(quit), "q"))
        return menu
    }

    private func actionItem(_ title: String, _ selector: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleSidebar() { actions.toggleSidebar?() }
    @objc private func openSettings() { actions.openSettings?() }
    @objc private func runSetupAgain() { actions.runSetupAgain?() }
    @objc private func openSearch() { actions.openSearch?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
