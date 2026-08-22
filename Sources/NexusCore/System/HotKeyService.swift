import AppKit
import Carbon.HIToolbox
import Foundation

/// Global hotkey via the Carbon HotKey API — still supported, and it needs no Accessibility
/// permission (§111.1). Main-actor confined: the Carbon handler dispatches on the main run loop.
@MainActor
public final class HotKeyService {
    public enum RegistrationError: Error, Equatable {
        case invalidShortcut
        case systemRefused(OSStatus)
    }

    private static let signature = FourCharCode(0x4E_58_53_31)   // 'NXS1'

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var current: KeyboardShortcut?

    /// Invoked on the main actor when the hotkey fires.
    public var onPressed: (() -> Void)?

    public init() {}

    public var registeredShortcut: KeyboardShortcut? { current }

    @discardableResult
    public func register(_ shortcut: KeyboardShortcut) -> Result<Void, RegistrationError> {
        guard shortcut.isValid else { return .failure(.invalidShortcut) }
        unregister()
        installHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            Log.system.error("RegisterEventHotKey failed with \(status, privacy: .public)")
            return .failure(.systemRefused(status))
        }
        hotKeyRef = reference
        current = shortcut
        Log.system.info("Global shortcut registered (key \(shortcut.keyCode, privacy: .public), modifiers \(shortcut.modifiers, privacy: .public))")
        return .success(())
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        current = nil
    }

    public func stop() {
        unregister()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            context,
            &eventHandler
        )
    }

    fileprivate func fire() {
        onPressed?()
    }
}

private let hotKeyEventHandler: EventHandlerUPP = { _, event, context in
    guard let context, let event else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else { return status }
    // Carbon dispatches this on the main run loop, so the service really is main-actor bound.
    let service = Unmanaged<HotKeyService>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { service.fire() }
    return noErr
}

extension KeyboardShortcut {
    /// `NSEvent.ModifierFlags` → Carbon modifier mask. Carbon virtual key codes already match
    /// `NSEvent.keyCode`, so the key itself needs no mapping table.
    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= KeyboardShortcut.cmdKey }
        if flags.contains(.option) { modifiers |= KeyboardShortcut.optionKey }
        if flags.contains(.control) { modifiers |= KeyboardShortcut.controlKey }
        if flags.contains(.shift) { modifiers |= KeyboardShortcut.shiftKey }
        return modifiers
    }

    public var displayString: String {
        var parts = ""
        if modifiers & Self.controlKey != 0 { parts += "⌃" }
        if modifiers & Self.optionKey != 0 { parts += "⌥" }
        if modifiers & Self.shiftKey != 0 { parts += "⇧" }
        if modifiers & Self.cmdKey != 0 { parts += "⌘" }
        return parts + Self.keyName(for: keyCode)
    }

    public static func keyName(for keyCode: UInt32) -> String {
        if let special = specialKeyNames[keyCode] { return special }
        let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        guard let source,
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress
            else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
    ]
}
