import AppKit
import NexusCore
import SwiftUI

/// One window: an icon, an application name, a title, and a thumbnail (design/window-switcher.md
/// §1, §6). The larger sibling of `WindowFlyoutView`'s `WindowCard` — same shape, drawn at grid
/// size rather than beside a bar.
struct SwitcherCard: View {
    let window: NexusWindow
    let preview: NSImage?
    /// Resolved once by `SwitcherViewModel.applicationURL(forBundleIdentifier:)` and memoized
    /// there — the card itself makes no LaunchServices calls, since its body runs on every
    /// hover, scroll and selection change (review finding, Task 5).
    let applicationURL: URL?
    let isSelected: Bool
    let isFocused: Bool
    let onActivate: () -> Void
    let onClose: () -> Void
    let onToggleSelection: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon = applicationIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(window.applicationName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(window.isMinimized ? String(localized: "Minimized") : displayTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                // The close button appears on hover only: a permanent one on every card turns a
                // grid of windows into a grid of buttons.
                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Close window"))
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.25))
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let icon = applicationIcon {
                    // No capture: the application's own icon, large. A grey rectangle says
                    // nothing about which window this is (§5).
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .opacity(window.isMinimized ? 0.5 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
        }
        .padding(10)
        .frame(width: SwitcherLayout.cardWidth, height: SwitcherLayout.cardHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColour, lineWidth: isSelected || isFocused ? 2 : 0)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // `onTapGesture`, not `nexusRow`, on purpose: a card has no drag or context menu to give,
        // and it needs `NSEvent.modifierFlags` to tell a plain click (activate) from a ⌘-click
        // (toggle selection) apart — `nexusRow`'s `onClick` takes no event, so it cannot make that
        // distinction. Reach for `nexusRow` for anything else in this module; reach for this only
        // if a future row also needs to read the click's modifiers.
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) { onToggleSelection() } else { onActivate() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.applicationName) — \(displayTitle)")
        .accessibilityValue(window.isMinimized ? String(localized: "minimized") : String(localized: "open"))
        .accessibilityHint(String(localized: "Brings this window to the front"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { onActivate() }
        .accessibilityAction(named: String(localized: "Close window")) { onClose() }
        .accessibilityAction(named: selectionActionName) { onToggleSelection() }
    }

    private var displayTitle: String {
        window.title.isEmpty ? String(localized: "Untitled window") : window.title
    }

    private var selectionActionName: String {
        isSelected ? String(localized: "Remove from selection") : String(localized: "Add to selection")
    }

    private var applicationIcon: NSImage? {
        applicationURL.map { IconCache.shared.icon(for: $0, size: 64) }
    }

    private var borderColour: Color {
        if isSelected { return .accentColor }
        return isFocused ? .white.opacity(0.6) : .clear
    }
}
