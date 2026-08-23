import AppKit
import NexusCore
import NexusUI

/// The composition root: the only place that builds concrete services and wires them together.
/// Library targets take protocols by injection and never see this type.
@MainActor
final class Composition {
    let events = EventBus()
    let configuration: ConfigurationController
    let permissions: PermissionService
    let applications: ApplicationService
    let applicationMonitor: ApplicationMonitor
    let windows: WindowService
    let windowMonitor: WindowMonitor
    let previews: WindowPreviewService
    let applicationIndex: ApplicationIndex
    let searchEngine: SearchEngine
    let actionRunner: ActionRunner
    let hotKeys = HotKeyService()
    let sidebarModel: SidebarViewModel
    let flyoutModel: WindowFlyoutViewModel
    let groupModel: GroupPopoverViewModel
    let nowPlaying: NowPlayingService
    let searchModel: SearchViewModel
    let panels: PanelController
    let reservedSpace: ReservedSpaceController
    let searchPanel: SearchPanelController
    let startMenuModel: StartMenuViewModel
    let startMenu: StartMenuPanelController
    let onboardingModel: OnboardingViewModel
    let dockReplacement: DockReplacementController

    private var settingsWindow: AuxiliaryWindowController?
    private var onboardingWindow: AuxiliaryWindowController?

    private var permissionTask: Task<Void, Never>?
    private var windowTitleTask: Task<Void, Never>?
    private var configurationTask: Task<Void, Never>?

    init() {
        configuration = ConfigurationController(store: ConfigurationStore(), events: events)
        permissions = PermissionService(events: events)
        applications = ApplicationService()
        applicationMonitor = ApplicationMonitor(service: applications, events: events)
        windows = WindowService(events: events)
        windowMonitor = WindowMonitor(service: windows, events: events)
        previews = WindowPreviewService()
        applicationIndex = ApplicationIndex(events: events)
        actionRunner = ActionRunner(applications: applications, windows: windows)

        let windowService = windows
        searchEngine = SearchEngine(
            providers: [
                ApplicationSearchProvider(
                    index: applicationIndex.snapshot,
                    runningBundleIdentifiers: { Self.runningBundleIdentifiers() }
                ),
                WindowSearchProvider(windows: { await windowService.cachedWindows() }),
                FileSearchProvider(),
                ActionSearchProvider(runningApplications: { Self.runningApplicationLabels() }),
            ]
        )

        sidebarModel = SidebarViewModel(
            applications: applications,
            configuration: configuration,
            events: events
        )
        flyoutModel = WindowFlyoutViewModel(
            service: windows,
            previewService: previews,
            permissions: permissions,
            events: events
        )
        searchModel = SearchViewModel(
            engine: searchEngine,
            configuration: configuration,
            index: applicationIndex.snapshot
        )
        groupModel = GroupPopoverViewModel()
        nowPlaying = NowPlayingService()
        panels = PanelController(
            model: sidebarModel,
            flyoutModel: flyoutModel,
            groupModel: groupModel,
            permissions: permissions,
            configuration: configuration,
            events: events
        )
        reservedSpace = ReservedSpaceController(
            configuration: configuration,
            events: events,
            windows: windows
        )
        searchPanel = SearchPanelController(model: searchModel)
        startMenuModel = StartMenuViewModel(
            index: applicationIndex.snapshot,
            configuration: configuration,
            launcher: applications
        )
        startMenu = StartMenuPanelController(model: startMenuModel, configuration: configuration)
        dockReplacement = DockReplacementController(
            configuration: configuration,
            dock: DockControlService()
        )
        onboardingModel = OnboardingViewModel(
            configuration: configuration,
            permissions: permissions,
            applications: applications,
            dockReplacement: dockReplacement
        )
    }

    func start() {
        // Materialise the loaded (or default) configuration so it is inspectable with `defaults`
        // from the first launch onwards.
        configuration.flush()

        sidebarModel.refreshWindowCounts = { [weak self] in self?.refreshWindowCounts() }
        // Window titles for the context menu. Accessibility-gated, so a refusal simply leaves the
        // cache empty and the menu without a window section (D60).
        sidebarModel.loadWindows = { [weak self] identity in
            guard let self else { return }
            Task { @MainActor [windows, sidebarModel] in
                let list = (try? await windows.windows(for: identity)) ?? []
                sidebarModel.setWindows(list, for: identity)
            }
        }
        sidebarModel.activateWindow = { [weak self] identity in
            guard let self else { return }
            Task { [windows] in try? await windows.activate(identity) }
        }
        // Reserved space needs the bar's geometry, and installs the move/resize observers only
        // while it is switched on (M12).
        reservedSpace.geometries = { [weak self] in self?.panels.reservedSpaceGeometries ?? [] }
        reservedSpace.observeGeometry = { [weak self] observes in
            self?.windowMonitor.setObservesGeometry(observes)
        }
        panels.onBarFrameChange = { [weak self] in self?.reservedSpace.barFrameChanged() }

        // A group's popover launches through the same path a bar row does, and dragging a member
        // out of it takes it out of the group (M13).
        // The popover follows its group through every edit, and closes when the group stops
        // existing (M13).
        sidebarModel.rowsDidChange = { [weak self] in self?.panels.groupsChanged() }
        groupModel.launch = { [weak self] item in self?.sidebarModel.activateOrLaunch(item) }
        groupModel.remove = { [weak self] item in self?.sidebarModel.removeFromGroup(item.id) }

        // Now playing (M15): the metadata is pushed by the players that publish it, the controls
        // are media keys, and the flyout follows the track.
        sidebarModel.mediaCommand = { [weak self] key in self?.nowPlaying.send(key) }
        sidebarModel.setPlayerVisible = { [weak self] visible in
            self?.nowPlaying.setPlayerVisible(visible)
        }
        sidebarModel.seekPlayer = { [weak self] seconds in self?.nowPlaying.seek(to: seconds) }

        // The bar's own Search part opens the palette beside itself when it is drawn as a box, and
        // in the middle of the screen when it is just an icon (D90).
        sidebarModel.openSearch = { [weak self] in
            guard let self else { return }
            searchPanel.show(configuration.configuration.search.barStyle == .field ? .bar : .centred)
        }
        sidebarModel.openStartMenu = { [weak self] in self?.showStartMenu() }
        applicationIndex.onIndexed = { [weak self] in self?.startMenuModel.indexChanged() }

        searchModel.frontmostApplication = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        searchModel.onExecute = { [weak self] result, secondary in self?.execute(result, secondary: secondary) }
        searchPanel.willShow = { [weak self] in self?.prepareSearch() }
        // The palette can open at the bar's Search row rather than mid-screen (M19). The bar's
        // geometry belongs to the panel controller, so the palette asks for it when it opens.
        searchPanel.barAnchor = { [weak self] in self?.panels.searchRowAnchor() }

        sidebarModel.start()
        flyoutModel.start()
        panels.start()
        reservedSpace.start()
        startNowPlaying()
        observeWindowTitles()
        searchPanel.start()
        startMenu.start()
        applicationMonitor.start()
        windowMonitor.start()
        applicationIndex.start()
        observeAccessibilityGrant()
        observeConfiguration()
        applySearchConfiguration()
        registerHotKey()
        dockReplacement.start()
        sidebarModel.windowCountsAreExact = permissions.status(of: .accessibility) == .granted
        refreshWindowCounts()

        if !configuration.configuration.onboarding.hasCompleted {
            runOnboarding()
        }
    }

    /// Mirrors the service's state into the sidebar. `@Observable` does not notify across types, so
    /// the bridge is an explicit callback rather than a timer that notices (§65).
    private func startNowPlaying() {
        // A player that publishes no metadata still names what it is playing in its window title —
        // VLC names the file, a browser names the tab (D76). Accessibility already reads those.
        nowPlaying.windowTitle = { [windows] bundleIdentifier in
            let identity = ApplicationIdentity(bundleIdentifier: bundleIdentifier)
            let list = (try? await windows.windows(for: identity)) ?? []
            return list.first { !$0.title.isEmpty }?.title
        }
        nowPlaying.onChange = { [weak self] _, isActive in
            guard let self else { return }
            sidebarModel.nowPlayingChanged(
                nowPlaying.display,
                isActive: isActive,
                players: nowPlaying.audioPlayers,
                position: nowPlaying.position
            )
        }
        nowPlaying.start()
        sidebarModel.nowPlayingChanged(
            nowPlaying.display,
            isActive: nowPlaying.isActive,
            players: nowPlaying.audioPlayers,
            position: nowPlaying.position
        )
    }

    // MARK: - Settings and onboarding

    func showSettings() {
        let controller = settingsWindow ?? AuxiliaryWindowController(title: String(localized: "Nexus Settings")) { [self] in
            SettingsView(
                configuration: configuration,
                permissions: permissions,
                dockReplacement: dockReplacement,
                validateShortcut: { [weak self] in self?.validate($0) },
                runOnboarding: { [weak self] in self?.runOnboarding() }
            )
        }
        settingsWindow = controller
        controller.show()
    }

    func runOnboarding() {
        onboardingModel.start()
        let controller = onboardingWindow ?? AuxiliaryWindowController(title: String(localized: "Set Up Nexus")) { [self] in
            OnboardingView(
                model: onboardingModel,
                validateShortcut: { [weak self] in self?.validate($0) }
            )
        }
        onboardingWindow = controller
        onboardingModel.onFinish = { [weak controller] in controller?.close() }
        // Closing the window counts as finishing: otherwise onboarding reappears on every
        // launch until someone reaches the last step.
        controller.show { [weak self] in
            guard let self, !configuration.configuration.onboarding.hasCompleted else { return }
            onboardingModel.finish()
        }
    }

    /// Applies a candidate shortcut for real and reports why it failed, so the recorder can put
    /// the previous binding back.
    private func validate(_ shortcut: KeyboardShortcut) -> String? {
        switch hotKeys.register(shortcut) {
        case .success:
            return nil
        case .failure(.invalidShortcut):
            return String(localized: "Add \u{2318}, \u{2325} or \u{2303} to the shortcut.")
        case .failure(.systemRefused):
            _ = hotKeys.register(configuration.configuration.search.shortcut)
            return String(localized: "That shortcut is already in use by another application.")
        }
    }

    /// Window counts, from the same Accessibility list the context menu shows so the two can never
    /// disagree (D61). `CGWindowListCopyWindowInfo` counts a browser's find bar and misses a
    /// Finder window, which is why it is only the fallback — and why the badge is hidden entirely
    /// while Accessibility is missing.
    private func refreshWindowCounts() {
        guard permissions.status(of: .accessibility) == .granted else {
            applicationMonitor.refresh()
            return
        }
        Task { [windows, applications, events] in
            guard let all = try? await windows.allWindows() else { return }
            var counts: [String: Int] = [:]
            for window in all {
                counts[window.identity.owner.bundleIdentifier, default: 0] += 1
            }
            await applications.updateWindowCounts(byBundleIdentifier: counts)
            events.publish(.applicationsChanged)
        }
    }

    // MARK: - Search

    private func prepareSearch() {
        applicationIndex.ensureBuilt()
        // Refresh the in-memory window snapshot on open — a user event, not a timer, and the
        // Window provider must never trigger AX traffic from a keystroke.
        Task { [windows] in _ = try? await windows.allWindows() }
    }

    private func execute(_ result: SearchResult, secondary: Bool) {
        let action = secondary ? (result.secondaryAction ?? result.action) : result.action
        let movesFocus = actionRunner.run(action)
        searchPanel.hide(restoreFocus: !movesFocus)
    }

    private func applySearchConfiguration() {
        let search = configuration.configuration.search
        var enabled: Set<SearchProviderID> = []
        if search.searchApplications { enabled.insert(.application) }
        if search.searchWindows { enabled.insert(.window) }
        if search.searchFiles { enabled.insert(.file) }
        if search.searchActions { enabled.insert(.action) }
        let maximumResults = search.maximumResults
        Task { [searchEngine] in
            await searchEngine.configure(enabled: enabled, maximumResults: maximumResults)
        }
    }

    // MARK: - Hotkey

    func registerHotKey() {
        hotKeys.onPressed = { [weak self] in self?.searchPanel.toggle() }
        guard configuration.configuration.general.globalShortcutEnabled else {
            hotKeys.unregister()
            return
        }
        let shortcut = configuration.configuration.search.shortcut
        if case .failure(let error) = hotKeys.register(shortcut) {
            Log.system.error("Could not register the global shortcut: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Observation

    /// The playing application's window title is its track: a track change shows up as a window
    /// title change, which `WindowMonitor` already publishes — and so does the player quitting.
    private func observeWindowTitles() {
        let stream = events.events()
        windowTitleTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .windowsChanged(let identity):
                    nowPlaying.windowsChanged(identity.bundleIdentifier)
                case .applicationTerminated(let identity):
                    // The player quit: nothing else will say so (D95).
                    nowPlaying.applicationTerminated(identity.bundleIdentifier)
                default:
                    continue
                }
            }
        }
    }

    private func observeConfiguration() {
        let stream = events.events()
        var lastShortcut = configuration.configuration.search.shortcut
        var lastEnabled = configuration.configuration.general.globalShortcutEnabled
        var lastPosition = configuration.configuration.appearance.position
        var lastShowStartMenu = configuration.configuration.general.showStartMenu
        configurationTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                guard case .configurationChanged(let updated) = event else { continue }
                self.applySearchConfiguration()
                if updated.search.shortcut != lastShortcut
                    || updated.general.globalShortcutEnabled != lastEnabled {
                    lastShortcut = updated.search.shortcut
                    lastEnabled = updated.general.globalShortcutEnabled
                    self.registerHotKey()
                }
                if updated.appearance.position != lastPosition {
                    lastPosition = updated.appearance.position
                    self.dockReplacement.sidebarPositionChanged()
                }
                if updated.general.showStartMenu != lastShowStartMenu {
                    lastShowStartMenu = updated.general.showStartMenu
                    self.sidebarModel.configurationChanged()
                }
            }
        }
    }

    /// Accessibility can be granted (or revoked) while Nexus is running. Observers are installed
    /// the moment it is granted and torn down when it is taken away — no restart, no crash (§65).
    private func observeAccessibilityGrant() {
        let stream = events.events()
        permissionTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                guard case .permissionChanged(.accessibility, let status) = event else { continue }
                self.sidebarModel.windowCountsAreExact = status == .granted
                switch status {
                case .granted:
                    self.windowMonitor.start()
                    self.refreshWindowCounts()
                case .denied, .notDetermined:
                    self.windowMonitor.stop()
                    Log.permissions.notice("Accessibility not granted; window features degraded")
                }
            }
        }
    }

    func showStartMenu() {
        applicationIndex.ensureBuilt()
        startMenu.toggle()
    }

    func statusItemActions() -> StatusItemController.Actions {
        StatusItemController.Actions(
            toggleSidebar: { [weak self] in self?.panels.toggleSidebar() },
            openSettings: { [weak self] in self?.showSettings() },
            runSetupAgain: { [weak self] in self?.runOnboarding() },
            openSearch: { [weak self] in self?.searchPanel.show() },
            isBarVisible: { [weak self] in self?.panels.isBarVisible ?? true },
            isDockHidden: { [weak self] in self?.dockReplacement.isDockHidden ?? false },
            restoreDock: { [weak self] in self?.dockReplacement.restoreNow() }
        )
    }

    func shutDown() {
        // Before anything else: the Dock comes back whenever Nexus is not running (D52).
        dockReplacement.stop()
        permissionTask?.cancel()
        configurationTask?.cancel()
        hotKeys.stop()
        settingsWindow?.stop()
        onboardingWindow?.stop()
        startMenu.stop()
        searchPanel.stop()
        applicationIndex.stop()
        windowTitleTask?.cancel()
        nowPlaying.stop()
        reservedSpace.stop()
        windowMonitor.stop()
        applicationMonitor.stop()
        panels.stop()
        flyoutModel.stop()
        sidebarModel.stop()
        configuration.flush()
        events.finishAll()
    }

    // MARK: - Snapshots for the Sendable providers

    nonisolated private static func runningBundleIdentifiers() -> Set<String> {
        Set(
            NSWorkspace.shared.runningApplications.compactMap {
                $0.activationPolicy == .regular ? $0.bundleIdentifier : nil
            }
        )
    }

    nonisolated private static func runningApplicationLabels() -> [(name: String, bundleIdentifier: String)] {
        NSWorkspace.shared.runningApplications.compactMap { running in
            guard running.activationPolicy == .regular,
                  let bundleIdentifier = running.bundleIdentifier,
                  let name = running.localizedName
            else { return nil }
            return (name, bundleIdentifier)
        }
    }
}
