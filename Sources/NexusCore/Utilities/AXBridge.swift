import ApplicationServices
import CoreGraphics
import Foundation

/// `_AXUIElementGetWindow` maps an AX element to its `CGWindowID`. It is long-stable SPI rather
/// than public API; `AX.windowID(of:)` treats its absence as "no window id", which costs the
/// preview for that window and nothing else (DESIGN_MVP §3.1).
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Thin, synchronous wrappers over the Accessibility API. Every call here blocks for as long as
/// the target application takes to answer, which is why callers live inside `WindowService`'s
/// actor and never on the main thread.
public enum AX {
    /// An unresponsive application must never freeze the sidebar (§65).
    public static let messagingTimeout: Float = 0.25

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system's "grant Accessibility" prompt. Only ever called from an explicit user
    /// action (§64).
    public static func promptForTrust() -> Bool {
        // The SDK exposes kAXTrustedCheckOptionPrompt as a mutable global; its value is the
        // documented, stable string.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func application(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    public static func value<T>(_ element: AXUIElement, _ attribute: String) throws -> T? {
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
        switch error {
        case .success:
            return raw as? T
        case .noValue, .attributeUnsupported:
            return nil
        case .invalidUIElement:
            throw NexusError.targetDisappeared
        case .apiDisabled:
            throw NexusError.permissionDenied(.accessibility)
        case .cannotComplete:
            throw NexusError.timedOut
        default:
            throw NexusError.systemDenied(error.rawValue)
        }
    }

    public static func windows(of application: AXUIElement) throws -> [AXUIElement] {
        let windows: [AXUIElement]? = try value(application, kAXWindowsAttribute)
        for window in windows ?? [] { AXUIElementSetMessagingTimeout(window, messagingTimeout) }
        return windows ?? []
    }

    public static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let raw: AXValue = try? value(element, attribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(raw, .cgPoint, &point) else { return nil }
        return point
    }

    public static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let raw: AXValue = try? value(element, attribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(raw, .cgSize, &size) else { return nil }
        return size
    }

    public static func windowID(of element: AXUIElement) -> CGWindowID? {
        var identifier: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &identifier) == .success, identifier != 0 else { return nil }
        return identifier
    }

    @discardableResult
    public static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    @discardableResult
    public static func set(_ element: AXUIElement, _ attribute: String, _ newValue: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, newValue) == .success
    }
}
