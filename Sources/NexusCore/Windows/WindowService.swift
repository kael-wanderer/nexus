import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public protocol WindowServing: Sendable {
    func windows(for application: ApplicationIdentity) async throws -> [NexusWindow]
    func allWindows() async throws -> [NexusWindow]
    func activate(_ window: WindowIdentity) async throws
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

    public init() {}

    public var isTrusted: Bool { AX.isTrusted }

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
        guard AX.isTrusted else { throw NexusError.permissionDenied(.accessibility) }
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

            // A subrole check keeps sheets, popovers and toolbars out of the window list.
            let subrole: String? = (try? AX.value(element, kAXSubroleAttribute)) ?? nil
            if let subrole, subrole != kAXStandardWindowSubrole { continue }

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

    public func allWindows() throws -> [NexusWindow] {
        guard AX.isTrusted else { throw NexusError.permissionDenied(.accessibility) }
        var all: [NexusWindow] = []
        for application in Self.regularApplications() {
            all.append(contentsOf: (try? windows(for: application)) ?? [])
        }
        return all
    }

    /// Raise before activating, or the application comes forward showing its previous window
    /// (DESIGN_MVP §3.2).
    public func activate(_ window: WindowIdentity) throws {
        guard AX.isTrusted else { throw NexusError.permissionDenied(.accessibility) }
        guard let element = elements[window.owner]?[window.number] else {
            throw NexusError.targetDisappeared
        }
        AX.set(element, kAXMinimizedAttribute, false as CFBoolean)
        AX.perform(element, kAXRaiseAction)
        let identity = window.owner
        Task { @MainActor in
            NSRunningApplication
                .runningApplications(withBundleIdentifier: identity.bundleIdentifier)
                .first?
                .activate()
        }
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
