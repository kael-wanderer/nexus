import AppKit
import NexusCore
import NexusUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var composition: Composition?
    private var statusItem: StatusItemController?
    private var configurationObserver: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = Log.signposter.beginInterval("cold start")
        NSApp.setActivationPolicy(.accessory)

        let composition = Composition()
        self.composition = composition

        let statusItem = StatusItemController(actions: composition.statusItemActions())
        statusItem.setVisible(composition.configuration.configuration.general.showInMenuBar)
        self.statusItem = statusItem

        composition.start()
        observeConfiguration(composition)

        Log.signposter.endInterval("cold start", state)
        if let elapsed = Log.secondsSinceProcessStart() {
            Log.app.notice("Nexus launched in \(elapsed * 1000, format: .fixed(precision: 0), privacy: .public) ms")
        } else {
            Log.app.notice("Nexus launched")
        }

        // Development hook: opens the search palette without a key press, so the activation
        // strategy (review Note 1) can be measured from a script.
        if ProcessInfo.processInfo.environment["NEXUS_DEBUG_SHOW_SEARCH"] != nil {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                composition.searchPanel.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        configurationObserver?.cancel()
        composition?.shutDown()
        Log.app.notice("Nexus terminating")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func observeConfiguration(_ composition: Composition) {
        let stream = composition.events.events()
        configurationObserver = Task { [weak self] in
            for await event in stream {
                guard case .configurationChanged(let configuration) = event else { continue }
                self?.statusItem?.setVisible(configuration.general.showInMenuBar)
            }
        }
    }
}
