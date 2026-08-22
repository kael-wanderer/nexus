import AppKit
import NexusCore
import SwiftUI

/// Records a new global shortcut. Escape cancels, Delete clears, and at least one non-shift
/// modifier is required (DESIGN_MVP §5).
public struct ShortcutRecorder: View {
    @Binding var shortcut: NexusCore.KeyboardShortcut
    /// Called with the candidate; returns an error message when registration failed, so the
    /// previous binding can be restored with an explanation.
    let validate: (NexusCore.KeyboardShortcut) -> String?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?

    public init(shortcut: Binding<NexusCore.KeyboardShortcut>, validate: @escaping (NexusCore.KeyboardShortcut) -> String?) {
        _shortcut = shortcut
        self.validate = validate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(isRecording ? String(localized: "Press a shortcut…") : shortcut.displayString) {
                    isRecording.toggle()
                }
                .frame(minWidth: 160)
                .accessibilityLabel(String(localized: "Global shortcut"))
                .accessibilityValue(shortcut.displayString)
                .accessibilityHint(String(localized: "Activates recording of a new keyboard shortcut"))

                if isRecording {
                    Text("⎋ cancels · ⌫ resets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording { startRecording() } else { stopRecording() }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        message = nil
        stopRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        if keyCode == 53 {                       // Escape
            isRecording = false
            return
        }
        if keyCode == 51 {                       // Delete
            apply(.optionSpace)
            return
        }
        let candidate = NexusCore.KeyboardShortcut(
            keyCode: keyCode,
            modifiers: NexusCore.KeyboardShortcut.carbonModifiers(from: event.modifierFlags)
        )
        guard candidate.isValid else {
            message = String(localized: "Add ⌘, ⌥ or ⌃ to the shortcut.")
            return
        }
        apply(candidate)
    }

    private func apply(_ candidate: NexusCore.KeyboardShortcut) {
        let previous = shortcut
        shortcut = candidate
        if let failure = validate(candidate) {
            shortcut = previous
            message = failure
        } else {
            message = nil
        }
        isRecording = false
    }
}

/// Command+Space registration *succeeds* but Spotlight still wins, because the system shortcut
/// is handled first — the failure is undetectable from the return code. So choosing it always
/// shows this (DESIGN_MVP §5).
public struct SpotlightGuideView: View {
    @State private var state = SpotlightShortcut.state()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Command+Space is Spotlight's shortcut"), systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text("macOS gives Command+Space to Spotlight, and it is handled before Nexus sees it. Nexus cannot change this for you.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 2) {
                Text("1. Open System Settings → Keyboard → Keyboard Shortcuts…")
                Text("2. Select Spotlight in the sidebar")
                Text("3. Turn off “Show Spotlight search”")
                Text("4. Come back — Command+Space is then Nexus's")
            }
            .font(.callout)

            HStack(spacing: 10) {
                Button(String(localized: "Open Keyboard Settings")) {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
                    else { return }
                    NSWorkspace.shared.open(url)
                }
                statusLabel
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Re-reading on appear is enough: the user leaves this screen to change the setting and
        // comes back. No poll.
        .onAppear { state = SpotlightShortcut.state() }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch state {
        case .enabled:
            Label(String(localized: "Spotlight shortcut still enabled"), systemImage: "circle.dashed")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .disabled:
            Label(String(localized: "Spotlight shortcut disabled"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.tint)
        case .unknown:
            EmptyView()
        }
    }
}
