import AppKit
import NexusCore
import SwiftUI

/// Everything applies live; nothing here needs a restart.
public struct SettingsView: View {
    @Bindable var configuration: ConfigurationController
    let permissions: any PermissionChecking
    let validateShortcut: (NexusCore.KeyboardShortcut) -> String?
    let runOnboarding: () -> Void

    public init(
        configuration: ConfigurationController,
        permissions: any PermissionChecking,
        validateShortcut: @escaping (NexusCore.KeyboardShortcut) -> String?,
        runOnboarding: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.permissions = permissions
        self.validateShortcut = validateShortcut
        self.runOnboarding = runOnboarding
    }

    public var body: some View {
        TabView {
            GeneralPane(configuration: configuration, runOnboarding: runOnboarding)
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            AppearancePane(configuration: configuration)
                .tabItem { Label(String(localized: "Appearance"), systemImage: "paintbrush") }
            BehaviorPane(configuration: configuration)
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

    @State private var loginState = LoginItemService.state
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "Launch Nexus at login"),
                    isOn: Binding(
                        get: { loginState == .enabled },
                        set: { setLaunchAtLogin($0) }
                    )
                )
                if loginState == .requiresApproval {
                    Text("Approve Nexus in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }

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
        // External changes (the user toggling the login item in System Settings) show up when
        // this pane comes back into view.
        .onAppear { loginState = LoginItemService.state }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemService.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = String(localized: "macOS refused the change. Open System Settings → General → Login Items.")
        }
        loginState = LoginItemService.state
        configuration.update { $0.general.launchAtLogin = loginState == .enabled }
    }

    private func binding(_ keyPath: WritableKeyPath<NexusConfiguration, Bool>) -> Binding<Bool> {
        configuration.binding(keyPath)
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @Bindable var configuration: ConfigurationController

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Position"), selection: configuration.binding(\.appearance.position)) {
                    Text("Left").tag(SidebarPosition.left)
                    Text("Right").tag(SidebarPosition.right)
                }
                .pickerStyle(.segmented)

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
        }
        .formStyle(.grouped)
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
            }
            Section {
                Toggle(String(localized: "Show running applications"), isOn: configuration.binding(\.behavior.showRunningApplications))
                Toggle(String(localized: "Show window count"), isOn: configuration.binding(\.behavior.showWindowCount))
                Toggle(String(localized: "Show favourites"), isOn: configuration.binding(\.behavior.showFavorites))
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
