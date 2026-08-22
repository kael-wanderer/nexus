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
    let searchModel: SearchViewModel
    let panels: PanelController
    let searchPanel: SearchPanelController
    let onboardingModel: OnboardingViewModel

    private var settingsWindow: AuxiliaryWindowController?
    private var onboardingWindow: AuxiliaryWindowController?

    private var permissionTask: Task<Void, Never>?
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
        panels = PanelController(
            model: sidebarModel,
            flyoutModel: flyoutModel,
            permissions: permissions,
            configuration: configuration,
            events: events
        )
        searchPanel = SearchPanelController(model: searchModel)
        onboardingModel = OnboardingViewModel(
            configuration: configuration,
            permissions: permissions,
            applications: applications
        )
    }

    func start() {
        // Materialise the loaded (or default) configuration so it is inspectable with `defaults`
        // from the first launch onwards.
        configuration.flush()

        sidebarModel.refreshWindowCounts = { [weak self] in self?.applicationMonitor.refresh() }
        sidebarModel.openSearch = { [weak self] in self?.searchPanel.show() }

        searchModel.frontmostApplication = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        searchModel.onExecute = { [weak self] result, secondary in self?.execute(result, secondary: secondary) }
        searchPanel.willShow = { [weak self] in self?.prepareSearch() }

        sidebarModel.start()
        flyoutModel.start()
        panels.start()
        searchPanel.start()
        applicationMonitor.start()
        windowMonitor.start()
        applicationIndex.start()
        observeAccessibilityGrant()
        observeConfiguration()
        applySearchConfiguration()
        registerHotKey()

        if !configuration.configuration.onboarding.hasCompleted {
            runOnboarding()
        }
    }

    // MARK: - Settings and onboarding

    func showSettings() {
        let controller = settingsWindow ?? AuxiliaryWindowController(title: String(localized: "Nexus Settings")) { [self] in
            SettingsView(
                configuration: configuration,
                permissions: permissions,
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

    private func observeConfiguration() {
        let stream = events.events()
        var lastShortcut = configuration.configuration.search.shortcut
        var lastEnabled = configuration.configuration.general.globalShortcutEnabled
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
                switch status {
                case .granted:
                    self.windowMonitor.start()
                case .denied, .notDetermined:
                    self.windowMonitor.stop()
                    Log.permissions.notice("Accessibility not granted; window features degraded")
                }
            }
        }
    }

    func statusItemActions() -> StatusItemController.Actions {
        StatusItemController.Actions(
            toggleSidebar: { [weak self] in self?.panels.toggleSidebar() },
            openSettings: { [weak self] in self?.showSettings() },
            runSetupAgain: { [weak self] in self?.runOnboarding() },
            openSearch: { [weak self] in self?.searchPanel.show() }
        )
    }

    func shutDown() {
        permissionTask?.cancel()
        configurationTask?.cancel()
        hotKeys.stop()
        settingsWindow?.stop()
        onboardingWindow?.stop()
        searchPanel.stop()
        applicationIndex.stop()
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
