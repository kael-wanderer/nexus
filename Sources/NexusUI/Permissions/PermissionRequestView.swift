import NexusCore
import SwiftUI

/// Explain-and-grant. Shown contextually the first time a window feature is used (Milestone 4)
/// and reused verbatim by the onboarding wizard (Milestone 6).
///
/// Denial is a designed state, not an error alert (§64): the copy says what the permission
/// unlocks and what still works without it.
public struct PermissionRequestView: View {
    public let permission: Permission
    public let onGrantTapped: () -> Void
    public let onDismiss: (() -> Void)?

    @State private var status: PermissionStatus
    /// Set once the user has been sent to System Settings, so the "already granted?" remedy is
    /// only offered to someone who has actually been there.
    @State private var didOpenSettings = false
    private let permissions: any PermissionChecking

    public init(
        permission: Permission,
        permissions: any PermissionChecking,
        onGrantTapped: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self.permission = permission
        self.permissions = permissions
        self.onGrantTapped = onGrantTapped
        self.onDismiss = onDismiss
        _status = State(initialValue: permissions.status(of: permission))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
                statusBadge
            }
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(fallback)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if status != .granted {
                HStack(spacing: 8) {
                    FlatActionRow(title: String(localized: "Open System Settings"), prominent: true) {
                        didOpenSettings = true
                        onGrantTapped()
                    }
                    if let onDismiss {
                        FlatActionRow(title: String(localized: "Not Now"), prominent: false) {
                            onDismiss()
                        }
                    }
                }
                if didOpenSettings, permission == .accessibility {
                    alreadyGrantedRemedy
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 320, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        // The single sanctioned poll (D13): it starts when this screen appears and is cancelled
        // the moment it goes away.
        .task {
            for await update in permissions.statusStream(for: permission) {
                status = update
            }
        }
    }

    /// macOS hands a process its Accessibility trust at launch. If the switch is already on in
    /// System Settings but this process still reads as untrusted, a restart is the only fix —
    /// so say so, and offer to do it.
    private var alreadyGrantedRemedy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("Already switched it on and Nexus still says no? macOS only hands out this permission when an app starts, so Nexus has to restart to pick it up.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            FlatActionRow(title: String(localized: "Restart Nexus"), prominent: false) {
                AppRelaunch.relaunch()
            }
        }
    }

    private var statusBadge: some View {
        Label(
            status == .granted
                ? String(localized: "Granted")
                : String(localized: "Not granted"),
            systemImage: status == .granted ? "checkmark.circle.fill" : "circle.dashed"
        )
        .font(.caption)
        .foregroundStyle(status == .granted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .accessibilityLabel(
            status == .granted
                ? String(localized: "Permission granted")
                : String(localized: "Permission not granted")
        )
    }

    private var symbol: String {
        switch permission {
        case .accessibility: "macwindow.on.rectangle"
        case .screenRecording: "camera.viewfinder"
        }
    }

    private var title: String {
        switch permission {
        case .accessibility: String(localized: "Accessibility")
        case .screenRecording: String(localized: "Screen Recording")
        }
    }

    private var explanation: String {
        switch permission {
        case .accessibility:
            String(localized: "Nexus needs Accessibility to list an application's windows, read their titles, and bring one to the front.")
        case .screenRecording:
            String(localized: "Screen Recording lets Nexus show a small picture of each window. It is optional.")
        }
    }

    private var fallback: String {
        switch permission {
        case .accessibility:
            String(localized: "Without it, everything else keeps working: pinned apps, launching, quitting, window counts and search.")
        case .screenRecording:
            String(localized: "Without it, window lists show titles only. Nexus will not ask again.")
        }
    }
}

/// A flat, custom-drawn action row. Standard `Button` chrome renders inactive inside a panel
/// that can never become key, so panels use this instead (DESIGN_MVP §2.1).
public struct FlatActionRow: View {
    public let title: String
    public let prominent: Bool
    public let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(title: String, prominent: Bool, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    public var body: some View {
        Text(title)
            .font(.callout.weight(prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fillStyle)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                    isHovered = hovering
                }
            }
            .nexusRow(onClick: action)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
    }

    private var fillStyle: AnyShapeStyle {
        if prominent { return AnyShapeStyle(.tint.opacity(isHovered ? 0.85 : 1)) }
        return AnyShapeStyle(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
    }
}
