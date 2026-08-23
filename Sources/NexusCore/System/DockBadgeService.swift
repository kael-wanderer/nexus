import AppKit
import ApplicationServices
import Foundation

/// The red badges — Mail's unread count, Messages', a download's progress — read out of the Dock's
/// own Accessibility tree (D106).
///
/// There is no other way to get them. `NSDockTile` and `UNNotificationContent.badge` are write-only
/// and per-process; `NSRunningApplication` has no such property, and `NSWorkspace` publishes no
/// notification for one. What does exist is `AXStatusLabel` on the Dock's `AXDockItem` children,
/// which is public API and is exactly the string the owning application set.
///
/// Three things that shape the design:
///
/// - **It needs Accessibility.** Without it every call returns `kAXErrorAPIDisabled` and there are
///   no badges, which is a missing decoration and nothing else.
/// - **It cannot be observed.** `AXObserverAddNotification` answers
///   `kAXErrorNotificationUnsupported` for value and title changes on dock items, so the only route
///   is to read. Nexus reads on the events it already has — the pointer entering the bar, an
///   application launching or quitting — and never on a timer.
/// - **The value is text, not a number.** "9999+" is a badge. It is mirrored as a string and never
///   parsed, because summing something an application chose the wording of is a bug waiting to be
///   filed.
///
/// The Dock keeps its tree whether or not it is on screen, so Nexus hiding the Dock (M20) does not
/// take the badges with it. An application with no dock item — not in the real Dock and not running
/// — has no badge to read, which is a real limit and not worth working around: a quit application's
/// badge is stale by definition.
public enum DockBadgeService {
    /// Badge label per bundle identifier, for every dock item that has one.
    ///
    /// Synchronous and AX-bound, so callers keep it off the main thread the same way `WindowService`
    /// does. Returns empty rather than throwing: no permission, no Dock, no badges — all three are
    /// the same answer to the only question the bar asks.
    public static func badges() -> [String: String] {
        guard AX.isTrusted, let dock = dockElement() else { return [:] }
        var result: [String: String] = [:]
        for item in items(in: dock) {
            guard let label: String = try? AX.value(item, statusLabelAttribute),
                  !label.isEmpty,
                  let identifier = bundleIdentifier(of: item)
            else { continue }
            result[identifier] = label
        }
        return result
    }

    /// Not a documented constant, but a documented *attribute*: the Dock publishes it on every
    /// application item, and it is listed by `AXUIElementCopyAttributeNames` like any other.
    private static let statusLabelAttribute = "AXStatusLabel"

    private static func dockElement() -> AXUIElement? {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first
        else { return nil }
        return AX.application(pid: dock.processIdentifier)
    }

    /// The Dock's items live in a single `AXList`. Its children are read rather than searched for by
    /// role: the tree is one level deep, and a recursive walk of somebody else's process is a cost
    /// with no payoff.
    private static func items(in dock: AXUIElement) -> [AXUIElement] {
        let lists: [AXUIElement] = (try? AX.value(dock, kAXChildrenAttribute)) ?? []
        return lists.flatMap { list -> [AXUIElement] in
            (try? AX.value(list, kAXChildrenAttribute)) ?? []
        }
    }

    /// `AXURL`, not `AXTitle`: the title is the display name, which is localised and which some
    /// processes report as the name of their helper binary. The bundle at the URL is the identity.
    private static func bundleIdentifier(of item: AXUIElement) -> String? {
        guard let url: URL = try? AX.value(item, kAXURLAttribute) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}
