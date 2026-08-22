import AppKit
import NexusCore
import SwiftUI

/// Five steps, all skippable. Skipping everything yields Option+Space, no permissions, a
/// left-hand sidebar and no pinned applications — a fully working launcher (§111.6).
@MainActor
@Observable
public final class OnboardingViewModel {
    public enum Step: Int, CaseIterable {
        case welcome
        case shortcut
        case permissions
        case sidebar
        case done

        var title: String {
            switch self {
            case .welcome: String(localized: "Welcome to Nexus")
            case .shortcut: String(localized: "Choose your search shortcut")
            case .permissions: String(localized: "Permissions")
            case .sidebar: String(localized: "Set up your sidebar")
            case .done: String(localized: "You're set")
            }
        }
    }

    public var step: Step = .welcome
    public private(set) var candidates: [NexusApplication] = []
    public var selectedForPinning: Set<String> = []

    @ObservationIgnored let configuration: ConfigurationController
    @ObservationIgnored let permissions: any PermissionChecking
    @ObservationIgnored private let applications: any ApplicationServing
    @ObservationIgnored public var onFinish: (() -> Void)?

    public init(
        configuration: ConfigurationController,
        permissions: any PermissionChecking,
        applications: any ApplicationServing
    ) {
        self.configuration = configuration
        self.permissions = permissions
        self.applications = applications
    }

    public func start() {
        step = .welcome
        selectedForPinning = Set(configuration.configuration.pinnedApplications)
        Task { candidates = await applications.runningApplications() }
    }

    public var isLastStep: Bool { step == .done }

    public func advance() {
        if step == .sidebar { applyPinning() }
        guard let next = Step(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
    }

    public func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Skips the remainder outright. Safe defaults are already in the configuration, so there is
    /// nothing to undo.
    public func skipAll() {
        finish()
    }

    public func togglePin(_ bundleIdentifier: String) {
        if selectedForPinning.contains(bundleIdentifier) {
            selectedForPinning.remove(bundleIdentifier)
        } else {
            selectedForPinning.insert(bundleIdentifier)
        }
    }

    private func applyPinning() {
        // Preserve the candidate order rather than a Set's arbitrary one.
        let ordered = candidates
            .map(\.identity.bundleIdentifier)
            .filter { selectedForPinning.contains($0) }
        configuration.update { $0.pinnedApplications = ordered }
    }

    public func finish() {
        configuration.update {
            $0.onboarding.hasCompleted = true
            $0.onboarding.completedVersion = NexusConfiguration.currentVersion
        }
        configuration.flush()
        Log.app.notice("Onboarding completed")
        onFinish?()
    }
}

public struct OnboardingView: View {
    @Bindable var model: OnboardingViewModel
    let validateShortcut: (NexusCore.KeyboardShortcut) -> String?

    public init(model: OnboardingViewModel, validateShortcut: @escaping (NexusCore.KeyboardShortcut) -> String?) {
        self.model = model
        self.validateShortcut = validateShortcut
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                content
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 460)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack {
            Text(model.step.title)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text("Step \(model.step.rawValue + 1) of \(OnboardingViewModel.Step.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome:
            VStack(alignment: .leading, spacing: 12) {
                Text("Nexus is a vertical dock and a search palette in one. It runs in the menu bar, keeps out of your way, and never changes your system settings.")
                Label("A sidebar you pin your applications to", systemImage: "sidebar.left")
                Label("A search palette for apps, windows and files", systemImage: "magnifyingglass")
                Label("Everything stays on this Mac", systemImage: "lock.shield")
            }

        case .shortcut:
            VStack(alignment: .leading, spacing: 14) {
                Text("Pick the shortcut that opens the search palette.")
                Picker("", selection: shortcutChoice) {
                    Text("⌥ Space — recommended, leaves Spotlight alone").tag(true)
                    Text("⌘ Space — needs one change in System Settings").tag(false)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if model.configuration.configuration.search.shortcut.isCommandSpace {
                    SpotlightGuideView()
                }

                LabeledContent(String(localized: "Or record your own")) {
                    ShortcutRecorder(
                        shortcut: model.configuration.binding(\.search.shortcut),
                        validate: validateShortcut
                    )
                }
            }

        case .permissions:
            VStack(alignment: .leading, spacing: 12) {
                Text("Both are optional. Nexus works as a launcher and a search palette with neither.")
                    .foregroundStyle(.secondary)
                ForEach(Permission.allCases, id: \.self) { permission in
                    PermissionRequestView(
                        permission: permission,
                        permissions: model.permissions,
                        onGrantTapped: { model.permissions.requestOrOpenSettings(permission) }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

        case .sidebar:
            VStack(alignment: .leading, spacing: 14) {
                Picker(String(localized: "Sidebar position"), selection: model.configuration.binding(\.appearance.position)) {
                    Text("Left").tag(SidebarPosition.left)
                    Text("Right").tag(SidebarPosition.right)
                }
                .pickerStyle(.segmented)

                Text("Pin the applications you use most. You can change this any time by dragging apps onto the sidebar.")
                    .foregroundStyle(.secondary)

                ForEach(model.candidates) { application in
                    Toggle(isOn: Binding(
                        get: { model.selectedForPinning.contains(application.identity.bundleIdentifier) },
                        set: { _ in model.togglePin(application.identity.bundleIdentifier) }
                    )) {
                        HStack(spacing: 8) {
                            Image(nsImage: IconCache.shared.icon(for: application.bundleURL, size: 20))
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(application.name)
                        }
                    }
                }
            }

        case .done:
            VStack(alignment: .leading, spacing: 12) {
                Text("The sidebar is on your \(model.configuration.configuration.appearance.position == .left ? "left" : "right"), and \(model.configuration.configuration.search.shortcut.displayString) opens search.")
                Text("Nexus lives in the menu bar. Everything here is in Settings, and you can run this setup again from there.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            if model.step != .welcome, model.step != .done {
                Button(String(localized: "Back")) { model.back() }
            }
            Button(String(localized: "Skip Setup")) { model.skipAll() }
                .buttonStyle(.link)
            Spacer()
            Button(model.isLastStep ? String(localized: "Done") : String(localized: "Continue")) {
                model.advance()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var shortcutChoice: Binding<Bool> {
        Binding(
            get: { !model.configuration.configuration.search.shortcut.isCommandSpace },
            set: { optionSpace in
                model.configuration.update {
                    $0.search.shortcut = optionSpace ? .optionSpace : .commandSpace
                }
            }
        )
    }
}
