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
            AppearancePane(configuration: configuration)
                .tabItem { Label(String(localized: "Appearance"), systemImage: "paintbrush") }
            BehaviorPane(configuration: configuration, permissions: permissions)
                .tabItem { Label(String(localized: "Behavior"), systemImage: "slider.horizontal.3") }
            SearchPane(configuration: configuration, validateShortcut: validateShortcut)
                .tabItem { Label(String(localized: "Search"), systemImage: "magnifyingglass") }
            PermissionsPane(permissions: permissions)
                .tabItem { Label(String(localized: "Permissions"), systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 430)
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
                Toggle(
                    String(localized: "Show the start menu button"),
                    isOn: binding(\.general.showStartMenu)
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

    var body: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "Use Nexus as primary Dock"),
                    isOn: Binding(
                        get: { configuration.configuration.dock.replacementEnabled },
                        set: { enabled in
                            dockReplacement.setEnabled(enabled)
                            isDockHidden = dockReplacement.isDockHidden
                        }
                    )
                )
                Text("Hides the macOS Dock while Nexus is running and restores it when Nexus quits.")
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
        }
        .formStyle(.grouped)
        .onAppear { isDockHidden = dockReplacement.isDockHidden }
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
                Picker(String(localized: "Display"), selection: displayBinding) {
                    Text("Main display").tag(DisplayPreferenceChoice.main)
                    Text("Display with the pointer").tag(DisplayPreferenceChoice.withMouse)
                }
            }
            Section {
                slider(String(localized: "Sidebar width"), \.appearance.width, AppearanceConfiguration.widthRange, step: 2)
                slider(String(localized: "Icon size"), \.appearance.iconSize, AppearanceConfiguration.iconSizeRange, step: 2)
                slider(String(localized: "Icon spacing"), \.appearance.iconSpacing, AppearanceConfiguration.iconSpacingRange, step: 1)
                slider(String(localized: "Corner radius"), \.appearance.cornerRadius, AppearanceConfiguration.cornerRadiusRange, step: 1)
                slider(String(localized: "Opacity"), \.appearance.opacity, AppearanceConfiguration.opacityRange, step: 0.05)
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

    private enum DisplayPreferenceChoice: Hashable { case main, withMouse }

    private var displayBinding: Binding<DisplayPreferenceChoice> {
        Binding(
            get: {
                if case .withMouse = configuration.configuration.appearance.display { return .withMouse }
                return .main
            },
            set: { choice in
                configuration.update { $0.appearance.display = choice == .withMouse ? .withMouse : .main }
            }
        )
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
                Toggle(String(localized: "Show running applications"), isOn: configuration.binding(\.behavior.showRunningApplications))
                Toggle(String(localized: "Show window count"), isOn: configuration.binding(\.behavior.showWindowCount))
                Toggle(String(localized: "Show favourites"), isOn: configuration.binding(\.behavior.showFavorites))
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

// MARK: - Search

struct SearchPane: View {
    @Bindable var configuration: ConfigurationController
    let validateShortcut: (NexusCore.KeyboardShortcut) -> String?

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Global shortcut")) {
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
