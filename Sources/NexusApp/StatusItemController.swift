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
        /// Read live, like `isDockHidden`: a menu item that only says "Toggle" leaves the one thing
        /// worth knowing — whether the bar is there — off the menu (D94).
        var isBarVisible: (() -> Bool)?
        /// Read live: Dock Replacement Mode is a visible change to the user's system, so the menu
        /// bar — the one piece of chrome an `LSUIElement` app always has — says so.
        var isDockHidden: (() -> Bool)?
        var restoreDock: (() -> Void)?
        var openGuide: (() -> Void)?
        /// Read live: an update found by the daily check shows here, since an `LSUIElement` app
        /// has no other place to say so without a notification permission.
        var offeredUpdate: (() -> UpdateAvailable?)?
    }

    /// Point size the template icon is drawn at. `NSStatusBar.system.thickness` is the ceiling.
    private static let iconHeight: CGFloat = 18

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
        // The menu bar is `NSStatusBar.system.thickness` (22 pt) tall, so 18 is about as large as
        // an icon gets before it touches the edges. The asset is 16 pt; drawing it at 18 matches
        // the system icons beside it.
        image?.size = NSSize(width: Self.iconHeight, height: Self.iconHeight)
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
        if let update = actions.offeredUpdate?() {
            let item = actionItem(
                String(localized: "Nexus \(update.displayVersion) Is Available…"), #selector(openUpdate), "")
            item.representedObject = update.releaseURL
            menu.addItem(item)
            menu.addItem(.separator())
        }
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
            let visible = actions.isBarVisible?() ?? true
            menu.addItem(actionItem(
                visible
                    ? String(localized: "Hide Nexus Bar")
                    : String(localized: "Show Nexus Bar"),
                #selector(toggleSidebar),
                ""
            ))
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        if actions.openSettings != nil {
            menu.addItem(actionItem(String(localized: "Settings…"), #selector(openSettings), ","))
        }
        if actions.runSetupAgain != nil {
            menu.addItem(actionItem(String(localized: "Run Setup Again…"), #selector(runSetupAgain), ""))
        }
        if actions.openGuide != nil {
            menu.addItem(actionItem(String(localized: "Nexus Guide"), #selector(openGuide), ""))
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
    @objc private func openGuide() { actions.openGuide?() }

    /// Opens the release page in the browser. Nothing is downloaded or installed by Nexus. The
    /// URL was already held to `https` when the feed was read.
    @objc private func openUpdate(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, url.scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func openSettings() { actions.openSettings?() }
    @objc private func runSetupAgain() { actions.runSetupAgain?() }
    @objc private func openSearch() { actions.openSearch?() }
    @objc private func restoreDock() { actions.restoreDock?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
