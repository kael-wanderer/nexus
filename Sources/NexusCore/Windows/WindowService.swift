import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public protocol WindowServing: Sendable {
    func windows(for application: ApplicationIdentity) async throws -> [NexusWindow]
    func allWindows() async throws -> [NexusWindow]
    func activate(_ window: WindowIdentity) async throws
    /// Presses the window's own close button. Nothing is removed from the snapshot here: a window
    /// with unsaved work puts up a sheet and stays, and the list must show what is actually there.
    func close(_ window: WindowIdentity) async throws
    /// Moves and resizes one window. `false` means the application would not have it — the caller
    /// is expected to stop asking rather than retry.
    @discardableResult
    func setFrame(_ frame: CGRect, for window: WindowIdentity) async throws -> Bool
    /// Presses whatever the application maps to ⌘N, if anything. No AX action means "open a new
    /// window" the way `activate` and `close` mean "raise" and "press the close button" — this is
    /// the closest approximation there is (D119).
    func newWindow(for application: ApplicationIdentity) async throws
}

/// Accessibility window enumeration. Everything here is synchronous IPC into another process
/// and blocks for as long as that process is unresponsive, so it lives on its own actor and
/// never on the main thread.
public actor WindowService: WindowServing {
    /// AX elements are only valid for the lifetime of the window they refer to; they are cached
    /// per application so `activate` does not have to re-enumerate, and thrown away whenever
    /// anything about that application changes.
    private var elements: [ApplicationIdentity: [CGWindowID: AXUIElement]] = [:]
    /// Applications that timed out. Skipped this pass, retried on their next AX event.
    private var unresponsive: Set<ApplicationIdentity> = []
    /// Last good enumeration, so search can read window titles without an AX round trip.
    private var snapshot: [ApplicationIdentity: [NexusWindow]] = [:]
    /// Revocation is only observable when a call is made — macOS publishes no TCC notification
    /// and Nexus does not poll (D13). The transition is detected here and announced once.
    private var wasTrusted = AX.isTrusted
    private let events: EventBus?

    public init(events: EventBus? = nil) {
        self.events = events
    }

    public var isTrusted: Bool { AX.isTrusted }

    /// Returns whether Accessibility is currently granted, publishing a `.permissionChanged`
    /// the first time it flips either way.
    @discardableResult
    private func checkTrust() -> Bool {
        let trusted = AX.isTrusted
        if trusted != wasTrusted {
            wasTrusted = trusted
            if !trusted {
                elements.removeAll()
                snapshot.removeAll()
                unresponsive.removeAll()
                Log.windows.notice("Accessibility was revoked while running; window features degraded")
            }
            events?.publish(.permissionChanged(.accessibility, trusted ? .granted : .denied))
        }
        return trusted
    }

    /// The whole window layer as last enumerated. Used by the search Window provider, which must
    /// stay in-memory fast (< 50 ms) and must never trigger AX traffic from a keystroke.
    public func cachedWindows() -> [NexusWindow] {
        snapshot.values.flatMap(\.self)
    }

    public func forget(_ application: ApplicationIdentity) {
        elements[application] = nil
        snapshot[application] = nil
        unresponsive.remove(application)
    }

    public func windows(for application: ApplicationIdentity) throws -> [NexusWindow] {
        guard checkTrust() else { throw NexusError.permissionDenied(.accessibility) }
        guard let pid = application.processIdentifier ?? Self.processIdentifier(for: application) else {
            throw NexusError.targetDisappeared
        }

        let signpost = Log.signposter.beginInterval("window enumeration")
        defer { Log.signposter.endInterval("window enumeration", signpost) }

        let applicationElement = AX.application(pid: pid)
        let windowElements: [AXUIElement]
        do {
            windowElements = try AX.windows(of: applicationElement)
        } catch NexusError.timedOut {
            unresponsive.insert(application)
            Log.windows.debug("\(application.bundleIdentifier, privacy: .public) did not answer in time; skipping")
            return snapshot[application] ?? []
        } catch NexusError.permissionDenied {
            checkTrust()
            throw NexusError.permissionDenied(.accessibility)
        } catch NexusError.targetDisappeared {
            forget(application)
            return []
        }

        unresponsive.remove(application)
        let name = Self.localizedName(for: pid) ?? application.bundleIdentifier

        var cache: [CGWindowID: AXUIElement] = [:]
        var windows: [NexusWindow] = []
        // Windows with no AX window id still list and activate; only their preview is lost.
        var syntheticID: CGWindowID = 1 << 31

        for element in windowElements {
            let title: String = (try? AX.value(element, kAXTitleAttribute)) ?? nil ?? ""
            let minimized: Bool = ((try? AX.value(element, kAXMinimizedAttribute)) ?? nil) ?? false
            let origin = AX.point(element, kAXPositionAttribute) ?? .zero
            let size = AX.size(element, kAXSizeAttribute) ?? .zero

            // Standard windows, plus anything currently minimized. The subrole filter keeps
            // sheets, popovers and toolbars out (`AXUnknown`, e.g. Brave's find bar) and the
            // elements with no subrole at all, which is what Finder's desktop window is — but a
            // window that is minimized stops calling itself standard (D100).
            let subrole: String? = (try? AX.value(element, kAXSubroleAttribute)) ?? nil
            guard Self.isListable(subrole: subrole, minimized: minimized) else { continue }

            let identifier: CGWindowID
            if let real = AX.windowID(of: element) {
                identifier = real
            } else {
                identifier = syntheticID
                syntheticID += 1
            }
            cache[identifier] = element
            windows.append(
                NexusWindow(
                    identity: WindowIdentity(owner: application, number: identifier),
                    title: title,
                    isMinimized: minimized,
                    frame: CGRect(origin: origin, size: size),
                    applicationName: name
                )
            )
        }

        elements[application] = cache
        snapshot[application] = windows
        return windows
    }

    /// Whether an AX element counts as one of the application's windows.
    ///
    /// Minimising a window changes its subrole: Finder's becomes `AXDialog` the moment it goes to
    /// the Dock, and a filter on `AXStandardWindow` alone loses it — which is why the window list
    /// used to shrink by one instead of gaining a minimized entry (D100).
    static func isListable(subrole: String?, minimized: Bool) -> Bool {
        if subrole == kAXStandardWindowSubrole { return true }
        return minimized && subrole != kAXUnknownSubrole
    }

    public func allWindows() throws -> [NexusWindow] {
        guard checkTrust() else { throw NexusError.permissionDenied(.accessibility) }
        var all: [NexusWindow] = []
        for application in Self.regularApplications() {
            all.append(contentsOf: (try? windows(for: application)) ?? [])
        }
        return all
    }

    /// Raise before activating, or the application comes forward showing its previous window
    /// (design/mvp.md §3.2).
    public func activate(_ window: WindowIdentity) throws {
        guard checkTrust() else { throw NexusError.permissionDenied(.accessibility) }
        guard let element = elements[window.owner]?[window.number] else {
            Log.windows.error("Activate failed: window \(window.number, privacy: .public) of \(window.owner.bundleIdentifier, privacy: .public) is no longer known")
            throw NexusError.targetDisappeared
        }
        AX.set(element, kAXMinimizedAttribute, false as CFBoolean)
        let raised = AX.perform(element, kAXRaiseAction)
        Log.windows.notice("Raise \(raised ? "succeeded" : "failed", privacy: .public) for window \(window.number, privacy: .public) of \(window.owner.bundleIdentifier, privacy: .public)")
        let identity = window.owner
        Task { @MainActor in
            NSRunningApplication
                .runningApplications(withBundleIdentifier: identity.bundleIdentifier)
                .first?
                .activate()
        }
    }

    public func close(_ window: WindowIdentity) throws {
        guard checkTrust() else { throw NexusError.permissionDenied(.accessibility) }
        guard let element = elements[window.owner]?[window.number] else {
            throw NexusError.targetDisappeared
        }
        // A window without a close button — a panel, a sheet's parent — is not an error worth
        // showing anybody: there is simply nothing to press.
        guard let button: AXUIElement = try AX.value(element, kAXCloseButtonAttribute) else {
            Log.windows.notice("No close button on window \(window.number, privacy: .public)")
            return
        }
        let pressed = AX.perform(button, kAXPressAction)
        Log.windows.notice("Close \(pressed ? "succeeded" : "failed", privacy: .public) for window \(window.number, privacy: .public)")
    }

    /// There is no "open a new window" API — no AX action, no `NSRunningApplication` method — so
    /// this walks the application's AX menu bar for the item bound to ⌘N and presses that
    /// (D119). Lives here rather than on the view model because it is the same synchronous IPC
    /// `windows(for:)` makes, on the same actor, with the same unresponsive-application and trust
    /// handling; a menu walk on the main thread would freeze Nexus for as long as the target takes
    /// to answer (`AXBridge.swift`'s own warning).
    public func newWindow(for application: ApplicationIdentity) throws {
        guard checkTrust() else { throw NexusError.permissionDenied(.accessibility) }
        guard let pid = application.processIdentifier ?? Self.processIdentifier(for: application) else {
            throw NexusError.targetDisappeared
        }
        let applicationElement = AX.application(pid: pid)
        let item: AXUIElement?
        do {
            item = try AX.menuItem(of: applicationElement, commandChar: "n")
        } catch NexusError.timedOut {
            unresponsive.insert(application)
            Log.windows.debug("\(application.bundleIdentifier, privacy: .public) did not answer in time; skipping")
            return
        } catch NexusError.permissionDenied {
            checkTrust()
            throw NexusError.permissionDenied(.accessibility)
        } catch NexusError.targetDisappeared {
            forget(application)
            return
        }
        unresponsive.remove(application)
        guard let item else {
            Log.windows.notice(
                "No \u{2318}N menu item for \(application.bundleIdentifier, privacy: .public); nothing to press"
            )
            return
        }
        AX.perform(item, kAXPressAction)
    }

    /// Moves and resizes one window, in Accessibility coordinates. Reserved Space (M12) is the
    /// only caller.
    ///
    /// Position is written twice around the resize: a window that refuses to shrink past its own
    /// minimum size would otherwise keep an origin that assumed it had.
    @discardableResult
    public func setFrame(_ frame: CGRect, for window: WindowIdentity) throws -> Bool {
        guard checkTrust() else { throw NexusError.permissionDenied(.accessibility) }
        guard let element = elements[window.owner]?[window.number] else {
            throw NexusError.targetDisappeared
        }
        guard AX.isSettable(element, kAXPositionAttribute) else { return false }

        let currentSize = AX.size(element, kAXSizeAttribute) ?? frame.size
        var moved = AX.set(element, kAXPositionAttribute, frame.origin)
        if frame.size != currentSize, AX.isSettable(element, kAXSizeAttribute) {
            AX.set(element, kAXSizeAttribute, frame.size)
            moved = AX.set(element, kAXPositionAttribute, frame.origin) || moved
        }
        if var stored = snapshot[window.owner],
           let index = stored.firstIndex(where: { $0.identity.number == window.number }) {
            stored[index].frame = frame
            snapshot[window.owner] = stored
        }
        return moved
    }

    // MARK: - Process lookup

    private static func processIdentifier(for application: ApplicationIdentity) -> pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: application.bundleIdentifier)
            .first?
            .processIdentifier
    }

    private static func localizedName(for pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    private static func regularApplications() -> [ApplicationIdentity] {
        NSWorkspace.shared.runningApplications.compactMap { running in
            guard running.activationPolicy == .regular,
                  let bundleIdentifier = running.bundleIdentifier
            else { return nil }
            return ApplicationIdentity(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: running.processIdentifier
            )
        }
    }
}
