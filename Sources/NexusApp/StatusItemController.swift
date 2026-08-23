import AppKit
import NexusCore

/// The menu-bar status item — the only chrome an `LSUIElement` app has.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var toggleSidebar: (() -> Void)?
        var openSettings: (() -> Void)?
        var runSetupAgain: (() -> Void)?
        var openSearch: (() -> Void)?
        /// Read live: Dock Replacement Mode is a visible change to the user's system, so the menu
        /// bar — the one piece of chrome an `LSUIElement` app always has — says so.
        var isDockHidden: (() -> Bool)?
        var restoreDock: (() -> Void)?
    }

    private var statusItem: NSStatusItem?
    private var actions: Actions

    init(actions: Actions) {
        self.actions = actions
        super.init()
    }

    var isVisible: Bool { statusItem != nil }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        if visible { install() } else { remove() }
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // The bundled template image; the SF Symbol is the fallback for an unbundled dev build,
        // where there are no resources to load.
        let image = NSImage(named: "NexusTemplate") ?? NSImage(
            systemSymbolName: "square.grid.2x2",
            accessibilityDescription: String(localized: "Nexus")
        )
        image?.isTemplate = true
        image?.accessibilityDescription = String(localized: "Nexus")
        item.button?.image = image
        item.button?.setAccessibilityLabel(String(localized: "Nexus"))
        let menu = buildMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        Log.app.debug("Status item installed")
    }

    private func remove() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        Log.app.debug("Status item removed")
    }

    /// Rebuilt on every open: the Dock rows depend on live state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in buildMenu().items {
            menu.addItem(item)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        if let isDockHidden = actions.isDockHidden {
            let hidden = isDockHidden()
            let status = NSMenuItem(
                title: hidden
                    ? String(localized: "macOS Dock: Hidden by Nexus")
                    : String(localized: "macOS Dock: Visible"),
                action: nil,
                keyEquivalent: ""
            )
            status.isEnabled = false
            menu.addItem(status)
            if hidden, actions.restoreDock != nil {
                menu.addItem(actionItem(String(localized: "Restore macOS Dock"), #selector(restoreDock), ""))
            }
            menu.addItem(.separator())
        }
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
    @objc private func restoreDock() { actions.restoreDock?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
