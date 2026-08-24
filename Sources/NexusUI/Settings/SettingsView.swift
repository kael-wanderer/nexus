import AppKit
import NexusCore
import SwiftUI

/// Everything applies live; nothing here needs a restart.
public struct SettingsView: View {
    @Bindable var configuration: ConfigurationController
    let permissions: any PermissionChecking
    let dockReplacement: DockReplacementController
    let validateShortcut: (NexusCore.KeyboardShortcut) -> String?
    let runOnboarding: () -> Void

    public init(
        configuration: ConfigurationController,
        permissions: any PermissionChecking,
        dockReplacement: DockReplacementController,
        validateShortcut: @escaping (NexusCore.KeyboardShortcut) -> String?,
        runOnboarding: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.permissions = permissions
        self.dockReplacement = dockReplacement
        self.validateShortcut = validateShortcut
        self.runOnboarding = runOnboarding
    }

    public var body: some View {
        TabView {
            GeneralPane(configuration: configuration, runOnboarding: runOnboarding)
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            DockPane(configuration: configuration, dockReplacement: dockReplacement)
                .tabItem { Label(String(localized: "Dock"), systemImage: "rectangle.bottomthird.inset.filled") }
            BarPane(configuration: configuration)
                .tabItem { Label(String(localized: "Bar"), systemImage: "rectangle.grid.1x2") }
            AppearancePane(configuration: configuration)
                .tabItem { Label(String(localized: "Appearance"), systemImage: "paintbrush") }
            BehaviorPane(configuration: configuration, permissions: permissions)
                .tabItem { Label(String(localized: "Behavior"), systemImage: "slider.horizontal.3") }
            ShortcutsPane(configuration: configuration, validateShortcut: validateShortcut)
                .tabItem { Label(String(localized: "Shortcuts"), systemImage: "keyboard") }
            SearchPane(configuration: configuration)
                .tabItem { Label(String(localized: "Search"), systemImage: "magnifyingglass") }
            PermissionsPane(permissions: permissions)
                .tabItem { Label(String(localized: "Permissions"), systemImage: "lock.shield") }
            AboutPane()
                .tabItem { Label(String(localized: "About"), systemImage: "info.circle") }
        }
        // Sized for the longest pane rather than the average one: a settings window that scrolls
        // hides the switch somebody came looking for. The window is resizable for the screens this
        // is still too tall for.
        .frame(width: 620, height: 790)
    }
}

// MARK: - General

struct GeneralPane: View {
    @Bindable var configuration: ConfigurationController
    let runOnboarding: () -> Void

    var body: some View {
        Form {
            Section {
                LaunchAtLoginToggle(configuration: configuration)

                Toggle(
                    String(localized: "Show Nexus in the menu bar"),
                    isOn: binding(\.general.showInMenuBar)
                )
                Toggle(
                    String(localized: "Enable the global shortcut"),
                    isOn: binding(\.general.globalShortcutEnabled)
                )
            }
            Section {
                Button(String(localized: "Run Setup Again…"), action: runOnboarding)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ keyPath: WritableKeyPath<NexusConfiguration, Bool>) -> Binding<Bool> {
        configuration.binding(keyPath)
    }
}

/// Shown in two places — General, and Dock, where a launcher that is not running is not a Dock
/// replacement — so it owns its own state rather than being duplicated.
struct LaunchAtLoginToggle: View {
    @Bindable var configuration: ConfigurationController

    @State private var loginState = LoginItemService.state
    @State private var loginError: String?

    var body: some View {
        Toggle(
            String(localized: "Launch Nexus at login"),
            isOn: Binding(get: { loginState == .enabled }, set: { setEnabled($0) })
        )
        // External changes (the user toggling the login item in System Settings) show up when
        // this pane comes back into view.
        .onAppear { loginState = LoginItemService.state }
        if !LoginItemService.isInInstallLocation {
            Text("Nexus is not in your Applications folder, so login would launch it from wherever it is running now. Move Nexus to Applications first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if loginState == .requiresApproval {
            Text("Approve Nexus in System Settings → General → Login Items.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let loginError {
            Text(loginError).font(.caption).foregroundStyle(.red)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            try LoginItemService.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = String(localized: "macOS refused the change. Open System Settings → General → Login Items.")
        }
        loginState = LoginItemService.state
        configuration.update { $0.general.launchAtLogin = loginState == .enabled }
    }
}

// MARK: - Dock

/// Dock Replacement Mode (D52) and the position that decides which edge Nexus owns. Position
/// lives here rather than in Appearance because this is the pane where it matters.
struct DockPane: View {
    @Bindable var configuration: ConfigurationController
    let dockReplacement: DockReplacementController

    @State private var isDockHidden = false

    /// One choice rather than a toggle, because it is one decision: either Nexus is the dock — in
    /// which case there should not be two — or it is a sidebar beside the real one (D78).
    private enum Mode: Hashable { case dock, sidebar }

    var body: some View {
        Form {
            Section {
                Picker(
                    String(localized: "Nexus is"),
                    selection: Binding(
                        get: { configuration.configuration.dock.replacementEnabled ? Mode.dock : .sidebar },
                        set: { mode in
                            dockReplacement.setEnabled(mode == .dock)
                            isDockHidden = dockReplacement.isDockHidden
                        }
                    )
                ) {
                    Text("My Dock").tag(Mode.dock)
                    Text("A sidebar").tag(Mode.sidebar)
                }
                .pickerStyle(.radioGroup)
                Text(configuration.configuration.dock.replacementEnabled
                    ? String(localized: "The macOS Dock stays hidden while Nexus is running, and comes back exactly as it was when Nexus quits.")
                    : String(localized: "The macOS Dock is left alone, so both are on screen. Choose “My Dock” to have Nexus replace it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                SidebarPositionPicker(configuration: configuration)
            }
            Section {
                LaunchAtLoginToggle(configuration: configuration)
            }
            Section {
                LabeledContent(String(localized: "macOS Dock")) {
                    Text(isDockHidden
                        ? String(localized: "Hidden by Nexus")
                        : String(localized: "Visible"))
                    .foregroundStyle(.secondary)
                }
                // Deliberately independent of the toggle above: this is the button for the case
                // where a previous run was killed and the flags no longer describe reality.
                Button(String(localized: "Restore macOS Dock")) {
                    dockReplacement.restoreNow()
                    isDockHidden = dockReplacement.isDockHidden
                }
                Text("⌥⌘D also toggles the Dock, whatever Nexus thinks.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section {
                Picker(String(localized: "Display"), selection: displayBinding) {
                    Text("Main display").tag(DisplayPreferenceChoice.main)
                    Text("Display with the pointer").tag(DisplayPreferenceChoice.withMouse)
                    Text("Every display").tag(DisplayPreferenceChoice.everyDisplay)
                }
                Text("With the pointer, the bar follows it across monitors. Every display gives each monitor its own bar, all showing the same applications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { isDockHidden = dockReplacement.isDockHidden }
    }

    /// Zero is not "no rows", it is "however many fit" — so it says so.
    private static func rowLimitLabel(_ limit: Int) -> String {
        limit == 0 ? String(localized: "Fit the screen") : "\(limit)"
    }

    private enum DisplayPreferenceChoice: Hashable { case main, withMouse, everyDisplay }

    private var displayBinding: Binding<DisplayPreferenceChoice> {
        Binding(
            get: {
                switch configuration.configuration.appearance.display {
                case .withMouse: .withMouse
                case .everyDisplay: .everyDisplay
                // A specific display, chosen in an older build or by hand, reads as Main here
                // rather than silently rewriting itself (D11).
                case .main, .specific: .main
                }
            },
            set: { choice in
                let preference: DisplayPreference = switch choice {
                case .withMouse: .withMouse
                case .everyDisplay: .everyDisplay
                case .main: .main
                }
                configuration.update { $0.appearance.display = preference }
            }
        )
    }

}

/// The four edges, shared by Settings and onboarding.
public struct SidebarPositionPicker: View {
    @Bindable var configuration: ConfigurationController

    public init(configuration: ConfigurationController) {
        self.configuration = configuration
    }

    public var body: some View {
        Picker(String(localized: "Position"), selection: configuration.binding(\.appearance.position)) {
            Text("Left").tag(SidebarPosition.left)
            Text("Right").tag(SidebarPosition.right)
            Text("Top").tag(SidebarPosition.top)
            Text("Bottom").tag(SidebarPosition.bottom)
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @Bindable var configuration: ConfigurationController

    var body: some View {
        Form {
            Section {
                slider(String(localized: "Sidebar width"), \.appearance.width, AppearanceConfiguration.widthRange, step: 2)
                slider(String(localized: "Icon size"), \.appearance.iconSize, AppearanceConfiguration.iconSizeRange, step: 2)
                slider(String(localized: "Icon spacing"), \.appearance.iconSpacing, AppearanceConfiguration.iconSpacingRange, step: 1)
                slider(String(localized: "Corner radius"), \.appearance.cornerRadius, AppearanceConfiguration.cornerRadiusRange, step: 1)
                slider(String(localized: "Opacity"), \.appearance.opacity, AppearanceConfiguration.opacityRange, step: 0.05)
            }
            Section {
                Picker(
                    String(localized: "Media player"),
                    selection: configuration.binding(\.appearance.mediaWidth)
                ) {
                    Text("Wide").tag(MediaWidth.wide)
                    Text("Compact").tag(MediaWidth.compact)
                }
                if configuration.configuration.appearance.mediaWidth == .wide {
                    Picker(
                        String(localized: "Wide player shows"),
                        selection: configuration.binding(\.appearance.mediaContent)
                    ) {
                        Text("Progress bar").tag(MediaContent.progress)
                        Text("What is playing").tag(MediaContent.title)
                    }
                }
                Text("A wide player takes four slots and shows the progress bar or the track inline. A left or right bar is always compact — a scrubber that narrow cannot be dragged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func slider(
        _ title: String,
        _ keyPath: WritableKeyPath<NexusConfiguration, Double>,
        _ range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        let binding = configuration.binding(keyPath)
        return LabeledContent(title) {
            HStack {
                Slider(value: binding, in: range, step: step)
                Text(String(format: "%.2f", binding.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .accessibilityLabel(title)
    }
}

// MARK: - Behavior

struct BehaviorPane: View {
    @Bindable var configuration: ConfigurationController
    let permissions: any PermissionChecking

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Auto-hide the sidebar"), isOn: configuration.binding(\.behavior.autoHide))
                if configuration.configuration.behavior.autoHide {
                    LabeledContent(String(localized: "Hide delay")) {
                        HStack {
                            Slider(value: configuration.binding(\.behavior.autoHideDelay), in: 0.1...2, step: 0.1)
                            Text(String(format: "%.1f s", configuration.configuration.behavior.autoHideDelay))
                                .font(.caption.monospacedDigit())
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
                Toggle(String(localized: "Expand on hover"), isOn: configuration.binding(\.behavior.hoverExpand))
                if !configuration.configuration.appearance.position.isVertical {
                    Text("Expanding is off while Nexus is on the top or bottom edge — growing taller on hover would shove every window on the screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    String(localized: "Show window previews on hover"),
                    isOn: configuration.binding(\.behavior.hoverPreview)
                )
                if configuration.configuration.behavior.hoverPreview {
                    LabeledContent(String(localized: "Hover delay")) {
                        HStack {
                            Slider(
                                value: configuration.binding(\.behavior.hoverPreviewDelay),
                                in: BehaviorConfiguration.hoverPreviewDelayRange,
                                step: 0.1
                            )
                            Text(
                                Measurement(
                                    value: configuration.configuration.behavior.hoverPreviewDelay,
                                    unit: UnitDuration.seconds
                                ).formatted(.measurement(width: .narrow))
                            )
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Toggle(
                    String(localized: "Keep windows off Nexus"),
                    isOn: configuration.binding(\.behavior.reserveSpace)
                )
                .disabled(configuration.configuration.behavior.autoHide)
                Text(reservedSpaceCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker(
                    String(localized: "Applications per group"),
                    selection: configuration.binding(\.behavior.groupCapacity)
                ) {
                    Text("9 (3 × 3)").tag(9)
                    Text("16 (4 × 4)").tag(16)
                }
                Text("Drag one icon onto another and hold to put them in a group.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker(String(localized: "Clicking an icon"), selection: configuration.binding(\.behavior.clickBehavior)) {
                    Text("Activates or launches the app").tag(ClickBehavior.activateOrLaunch)
                    Text("Shows its windows").tag(ClickBehavior.showWindowList)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Says why the toggle is unavailable, or what it needs, rather than leaving a dimmed row with
    /// no explanation.
    private var reservedSpaceCaption: String {
        if configuration.configuration.behavior.autoHide {
            return String(localized: "A bar that hides cannot hold space; turn off auto-hide first.")
        }
        if permissions.status(of: .accessibility) != .granted {
            return String(localized: "Needs Accessibility, which is also what the window list uses. Grant it in the Permissions tab.")
        }
        return String(localized: "Windows that open over Nexus are moved off it. Full-screen windows are left alone.")
    }
}

// MARK: - Shortcuts

/// Every global shortcut in one place. They used to live in the tab of the feature they belonged
/// to, which answered "how do I change the palette's shortcut" and never "what is bound to what"
/// (design/window-switcher.md §9).
struct ShortcutsPane: View {
    @Bindable var configuration: ConfigurationController
    let validateShortcut: (NexusCore.KeyboardShortcut) -> String?

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Open search")) {
                    ShortcutRecorder(
                        shortcut: configuration.binding(\.search.shortcut),
                        validate: validateShortcut
                    )
                }
                if configuration.configuration.search.shortcut.isCommandSpace {
                    SpotlightGuideView()
                }
            }
            Section {
                Toggle(
                    String(localized: "Keyboard access to the bar"),
                    isOn: Binding(
                        get: { configuration.configuration.general.focusBarShortcut != nil },
                        set: { on in
                            configuration.update { $0.general.focusBarShortcut = on ? .focusBarDefault : nil }
                        }
                    )
                )
                if let current = configuration.configuration.general.focusBarShortcut {
                    LabeledContent(String(localized: "Focus the bar")) {
                        ShortcutRecorder(
                            shortcut: Binding(
                                get: { current },
                                set: { new in configuration.update { $0.general.focusBarShortcut = new } }
                            ),
                            validate: { _ in nil }
                        )
                    }
                }
                Text("Puts the keyboard on the bar: arrows move along it, Return opens what is focused, Escape gives the keyboard back. It also returns on its own after ten seconds of nothing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(
                    String(localized: "Window switcher"),
                    isOn: Binding(
                        get: { configuration.configuration.general.windowSwitcherShortcut != nil },
                        set: { on in
                            configuration.update {
                                $0.general.windowSwitcherShortcut = on ? .windowSwitcherDefault : nil
                            }
                        }
                    )
                )
                if let current = configuration.configuration.general.windowSwitcherShortcut {
                    LabeledContent(String(localized: "Open the switcher")) {
                        ShortcutRecorder(
                            shortcut: Binding(
                                get: { current },
                                set: { new in configuration.update { $0.general.windowSwitcherShortcut = new } }
                            ),
                            validate: { _ in nil }
                        )
                    }
                }
                Text("A grid of every open window: type to filter it, arrows to move, Return to go there. ⌘-click cards and Add Stack puts their applications in the bar as a group.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !Self.conflicts(in: configuration.configuration).isEmpty {
                Section {
                    Text("Two shortcuts are the same combination. Only the first one registered will work.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Combinations claimed by more than one slot. Carbon registers the first and refuses the
    /// rest, which is silent — so it is said here instead.
    ///
    /// `nonisolated`: `ShortcutsPane` infers `@MainActor` from `View`, and this touches no view
    /// state — leaving it isolated would make it a runtime trap to call from the test's
    /// synchronous, non-main-actor context, rather than a compile error to catch here instead.
    nonisolated static func conflicts(in configuration: NexusConfiguration) -> Set<NexusCore.KeyboardShortcut> {
        let all = [
            configuration.search.shortcut,
            configuration.general.focusBarShortcut,
            configuration.general.windowSwitcherShortcut,
        ].compactMap { $0 }
        var seen: Set<NexusCore.KeyboardShortcut> = []
        var repeated: Set<NexusCore.KeyboardShortcut> = []
        for shortcut in all where !seen.insert(shortcut).inserted { repeated.insert(shortcut) }
        return repeated
    }
}

// MARK: - Search

struct SearchPane: View {
    @Bindable var configuration: ConfigurationController

    var body: some View {
        Form {
            Section {
                Picker(
                    String(localized: "In the bar, show"),
                    selection: configuration.binding(\.search.barStyle)
                ) {
                    ForEach(SearchBarStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                Text("A box takes three slots and opens the palette beside itself; an icon takes one and opens it in the middle of the screen. Nothing takes the part off the bar altogether — the shortcut still opens the palette. The shortcut always opens it in the middle. Typing happens in the palette either way — the bar cannot take keyboard focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Inside the palette, ⇥ or ⌃1…⌃6 narrows a search to applications, files or folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(String(localized: "Search applications"), isOn: configuration.binding(\.search.searchApplications))
                Toggle(String(localized: "Search windows"), isOn: configuration.binding(\.search.searchWindows))
                Toggle(String(localized: "Search files"), isOn: configuration.binding(\.search.searchFiles))
                Toggle(String(localized: "Search actions"), isOn: configuration.binding(\.search.searchActions))
            }
            Section {
                Stepper(
                    String(localized: "Maximum results: \(configuration.configuration.search.maximumResults)"),
                    value: configuration.binding(\.search.maximumResults),
                    in: 5...50,
                    step: 5
                )
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions

struct PermissionsPane: View {
    let permissions: any PermissionChecking

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Permission.allCases, id: \.self) { permission in
                    PermissionRequestView(
                        permission: permission,
                        permissions: permissions,
                        onGrantTapped: { permissions.requestOrOpenSettings(permission) }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Text("Nexus never asks for a permission at launch and never re-asks after a refusal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }
}

// MARK: - Binding helper

extension ConfigurationController {
    /// Two-way binding straight onto the configuration, so every control writes through the one
    /// debounced, event-publishing path.
    public func binding<Value>(_ keyPath: WritableKeyPath<NexusConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { self.configuration[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}


// MARK: - Bar

/// What the bar has in it. Not "how it looks" (Appearance) and not "where it is" (Dock): the rows
/// themselves, and how many of them there may be.
struct BarPane: View {
    @Bindable var configuration: ConfigurationController

    var body: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "Start menu button"),
                    isOn: configuration.binding(\.general.showStartMenu)
                )
                if configuration.configuration.general.showStartMenu {
                    Picker(
                        String(localized: "Opens from"),
                        selection: configuration.binding(\.appearance.startMenuCorner)
                    ) {
                        Text("Bottom left").tag(StartMenuCorner.bottomLeading)
                        Text("Bottom right").tag(StartMenuCorner.bottomTrailing)
                        Text("Top left").tag(StartMenuCorner.topLeading)
                        Text("Top right").tag(StartMenuCorner.topTrailing)
                    }
                }
                Text("A browsable grid of everything installed, for the applications you cannot name from memory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(
                    String(localized: "What is playing"),
                    isOn: configuration.binding(\.general.showNowPlaying)
                )
                Text("A row in the bar with transport controls, and the track for players that publish it. It appears only while something is playing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(String(localized: "Running applications"), isOn: configuration.binding(\.behavior.showRunningApplications))
                Toggle(String(localized: "Minimized windows"), isOn: configuration.binding(\.behavior.showMinimizedWindows))
                Text("Minimized windows sit before the Trash, newest first, at most three.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(String(localized: "Window count badges"), isOn: configuration.binding(\.behavior.showWindowCount))
                Toggle(String(localized: "Favourites"), isOn: configuration.binding(\.behavior.showFavorites))
            }
            Section {
                Toggle(
                    String(localized: "Hide over full-screen apps"),
                    isOn: configuration.binding(\.behavior.hideOverFullScreen)
                )
                Text("A display showing a full-screen window shows no bar, which is what the Dock does. Only that display: a bar on another monitor stays.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(
                    String(localized: "Show folder preview on hover"),
                    isOn: configuration.binding(\.behavior.folderHoverPreview)
                )
                Text("Resting on a pinned folder shows what is in it, without a click. Off, a folder opens its stack when clicked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(
                    String(localized: "Suggest groups by category"),
                    isOn: configuration.binding(\.behavior.suggestCategoryGroups)
                )
                Text("A newly pinned application joins the group its category already has, and its menu offers that group by name. Nothing is created and nothing is scanned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(
                    String(localized: "Group colours and emoji"),
                    isOn: configuration.binding(\.behavior.groupColorsAndEmoji)
                )
                Text("A group can carry a colour and an emoji, chosen where its name is edited. Off hides both without forgetting them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Stepper(
                    value: configuration.binding(\.appearance.pinnedLimit),
                    in: AppearanceConfiguration.rowLimitRange
                ) {
                    LabeledContent(
                        String(localized: "Most pinned rows"),
                        value: Self.rowLimitLabel(configuration.configuration.appearance.pinnedLimit)
                    )
                }
                Stepper(
                    value: configuration.binding(\.appearance.runningLimit),
                    in: AppearanceConfiguration.rowLimitRange
                ) {
                    LabeledContent(
                        String(localized: "Most running rows"),
                        value: Self.rowLimitLabel(configuration.configuration.appearance.runningLimit)
                    )
                }
                Text("The bar grows until it runs out of screen, then each section scrolls inside itself. Trash and Search always stay in view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Zero is not "no rows", it is "however many fit" — so it says so.
    private static func rowLimitLabel(_ limit: Int) -> String {
        limit == 0 ? String(localized: "Fit the screen") : "\(limit)"
    }
}

// MARK: - About

/// What is running, and where it came from.
struct AboutPane: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "MIT Licensed."
    }

    private var location: String {
        Bundle.main.bundleURL.deletingLastPathComponent().path
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nexus").font(.title2.weight(.semibold))
                        Text("Version \(version) (\(build))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("A dock and a launcher for macOS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent(String(localized: "Author"), value: "Cong Bui")
                LabeledContent(String(localized: "Licence"), value: copyright)
                LabeledContent(String(localized: "Running from"), value: location)
            }
            Section {
                Button(String(localized: "Copy Version Details")) {
                    let summary = """
                    Nexus \(version) (\(build))
                    macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
                    Running from \(location)
                    """
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary, forType: .string)
                }
                Text("Paste this into a bug report, so the answer is not a guess.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

