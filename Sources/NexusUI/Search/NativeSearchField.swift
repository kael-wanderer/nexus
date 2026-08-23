import AppKit
import SwiftUI

/// SwiftUI `TextField` focus is unreliable in a window whose application is not active, which is
/// exactly the situation the non-activating palette creates. An `NSTextField` behind
/// `NSViewRepresentable` is the accepted cost (review Note 1).
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontSize: CGFloat
    var onMove: (Int) -> Void
    var onSubmit: (Bool) -> Void
    var onCancel: () -> Void
    /// `⇥` and `⇧⇥`. The field editor reports them as commands, so they never reach a key monitor
    /// and never move focus out of a palette that has exactly one control.
    var onCycleScope: ((Int) -> Void)?
    /// Takes first responder as soon as it has a window, with what is in it selected. The palette's
    /// panel exists before its field does, so `SearchPanelController` focuses it from outside; the
    /// group popover's field is built by a SwiftUI branch that only appears once the title has been
    /// clicked, so it has to do it itself (D104).
    var focusesItself = false

    func makeNSView(context: Context) -> NSTextField {
        let field = focusesItself ? SelfFocusingTextField(string: text) : NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: .regular)
        field.placeholderString = placeholder
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byTruncatingTail
        field.setAccessibilityLabel(placeholder)
        field.setAccessibilityRole(.textField)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Focuses itself when it lands in a window. `@FocusState` cannot: the panel is made key in the
    /// same turn the field is created, and SwiftUI's focus arrives before the window's does.
    private final class SelfFocusingTextField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window.firstResponder !== currentEditor() else { return }
            window.makeFirstResponder(self)
            currentEditor()?.selectAll(nil)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeSearchField

        init(_ parent: NativeSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(false)
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit(true)
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
            case #selector(NSResponder.insertTab(_:)):
                guard let cycle = parent.onCycleScope else { return false }
                cycle(1)
            case #selector(NSResponder.insertBacktab(_:)):
                guard let cycle = parent.onCycleScope else { return false }
                cycle(-1)
            default:
                return false
            }
            return true
        }
    }
}
