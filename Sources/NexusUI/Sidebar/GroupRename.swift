import AppKit
import NexusCore

/// Renaming a group from its row's context menu happens in an alert. The popover has its own
/// title field (D104); this is for the row, where there is nowhere to type.
///
/// The alert lands on the screen the pointer is on, which is not where AppKit would put it
/// (D102).
@MainActor
public enum GroupRename {
    public static func prompt(for group: SidebarGroup, model: SidebarViewModel) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Group")
        alert.informativeText = String(localized: "Choose a name for this group of applications.")
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = group.name
        field.placeholderString = ApplicationCategory.fallbackName
        alert.accessoryView = field
        NSApp.activate()
        alert.window.initialFirstResponder = field
        // `runModal()` re-centres the window on the main display as it starts, so positioning it
        // beforehand is overwritten. Moving it from inside the modal loop is what sticks — the
        // modal session runs the run loop, so a block queued for `.modalPanel` runs once the alert
        // is up (D102).
        let pointer = NSEvent.mouseLocation
        RunLoop.main.perform(inModes: [.modalPanel, .common]) {
            MainActor.assumeIsolated {
                alert.window.setFrame(
                    Design.centred(alert.window.frame.size, onScreenUnder: pointer),
                    display: true
                )
            }
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.renameGroup(group.id, to: field.stringValue)
    }
}
