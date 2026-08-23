import AppKit
import CoreGraphics
import Foundation
import NexusCore

/// Keeps other applications' windows off the bar (M12).
///
/// macOS reserves screen space for the menu bar and the Dock and for nothing else — there is no
/// public API that shrinks `visibleFrame` on a third party's behalf. So the space cannot be made
/// unavailable; windows can only be moved out of it, through the Accessibility permission the
/// window list already needs. A window can therefore *open* over the bar and be nudged a moment
/// later, which is the honest ceiling of doing this without private API.
@MainActor
public final class ReservedSpaceController {
    /// Everything the nudge needs to know about the screen, in Cocoa coordinates. `nil` from the
    /// provider means "not now" — the bar is hidden, suppressed, or auto-hiding.
    public struct Geometry: Sendable, Equatable {
        public var bar: CGRect
        public var visible: CGRect
        public var display: CGRect
        public var position: SidebarPosition

        public init(bar: CGRect, visible: CGRect, display: CGRect, position: SidebarPosition) {
            self.bar = bar
            self.visible = visible
            self.display = display
            self.position = position
        }
    }

    /// An application that puts a window straight back is not one to argue with.
    static let maximumAttempts = 4
    static let attemptWindow = Duration.seconds(2)

    private let configuration: ConfigurationController
    private let events: EventBus
    private let windows: any WindowServing

    /// Set by the composition root: the bar's own geometry, and the switch that installs the
    /// move/resize observers only while this is running.
    public var geometry: (() -> Geometry?)?
    public var observeGeometry: ((Bool) -> Void)?
    /// Trust check, injected so tests do not depend on the machine's Accessibility grant.
    public var isTrusted: () -> Bool = { AX.isTrusted }
    /// Primary display height, for the Cocoa → Accessibility flip.
    public var primaryHeight: () -> CGFloat = { ScreenGeometry.primaryHeight }
    /// Applications to sweep. Nexus is not one of them: its own panels are the thing being
    /// reserved for.
    public var runningApplications: () -> [ApplicationIdentity] = { ReservedSpaceController.regularApplications() }

    private var eventTask: Task<Void, Never>?
    private var isObserving = false
    private var attempts: [String: (count: Int, since: ContinuousClock.Instant)] = [:]
    private var blocked: Set<String> = []
    private var sweepTask: Task<Void, Never>?

    public init(
        configuration: ConfigurationController,
        events: EventBus,
        windows: any WindowServing
    ) {
        self.configuration = configuration
        self.events = events
        self.windows = windows
    }

    // MARK: - Lifecycle

    public func start() {
        let stream = events.events()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .windowGeometrySettled(let identity), .windowsChanged(let identity):
                    self.schedule(identity)
                case .applicationLaunched(let identity):
                    self.schedule(identity)
                case .applicationTerminated(let identity):
                    self.forget(identity)
                case .configurationChanged, .displaysChanged:
                    self.apply()
                case .permissionChanged(.accessibility, _):
                    self.apply()
                default:
                    continue
                }
            }
        }
        apply()
    }

    public func stop() {
        eventTask?.cancel()
        eventTask = nil
        sweepTask?.cancel()
        sweepTask = nil
        setObserving(false)
    }

    /// The bar moved, resized or changed edge: what counts as clear of it just changed.
    public func barFrameChanged() {
        apply()
    }

    /// Turns the whole thing on or off from current state, and sweeps once when it is on.
    public func apply() {
        guard isEnabled, let geometry = geometry?() else {
            setObserving(false)
            attempts.removeAll()
            return
        }
        setObserving(true)
        sweepTask?.cancel()
        sweepTask = Task { [weak self] in
            await self?.sweep(geometry)
        }
    }

    /// `reserveSpace` on, `autoHide` off, Accessibility granted. Auto-hide is deliberately
    /// exclusive: a bar that comes and goes cannot own space, and pushing windows aside every
    /// time it appeared without ever putting them back would be worse than doing nothing.
    public var isEnabled: Bool {
        let behavior = configuration.configuration.behavior
        return behavior.reserveSpace && !behavior.autoHide && isTrusted()
    }

    // MARK: - Nudging

    /// Sweeps every application. Used on enable, on a bar move and on a display change.
    func sweep(_ geometry: Geometry) async {
        for identity in runningApplications() {
            await nudge(identity, geometry)
        }
    }

    /// Moves whatever this application has over the bar. Windows the user is still dragging are
    /// not seen here: the move/resize events only arrive once they settle.
    func nudge(_ identity: ApplicationIdentity, _ geometry: Geometry) async {
        let height = primaryHeight()
        let available = ScreenGeometry.flipped(
            SidebarLayout.availableFrame(
                besides: geometry.bar,
                in: geometry.visible,
                position: geometry.position
            ),
            primaryHeight: height
        )
        let display = ScreenGeometry.flipped(geometry.display, primaryHeight: height)

        let list = (try? await windows.windows(for: identity)) ?? []
        for window in list where !window.isMinimized {
            guard let target = SidebarLayout.fit(window.frame, into: available, display: display)
            else {
                // Compliant: forget its history, so a window the user drags onto the bar once an
                // hour never accumulates its way into being ignored.
                attempts[window.id] = nil
                continue
            }
            guard shouldNudge(window.id) else { continue }
            let moved = (try? await windows.setFrame(target, for: window.identity)) ?? false
            if !moved { block(window.id, reason: "would not be moved") }
        }
    }

    private func schedule(_ identity: ApplicationIdentity) {
        guard isEnabled, let geometry = geometry?() else { return }
        Task { [weak self] in await self?.nudge(identity, geometry) }
    }

    private func shouldNudge(_ key: String) -> Bool {
        guard !blocked.contains(key) else { return false }
        let now = ContinuousClock.now
        var record = attempts[key] ?? (count: 0, since: now)
        if now - record.since > Self.attemptWindow { record = (count: 0, since: now) }
        record.count += 1
        attempts[key] = record
        guard record.count <= Self.maximumAttempts else {
            block(key, reason: "keeps putting it back")
            return false
        }
        return true
    }

    private func block(_ key: String, reason: String) {
        guard blocked.insert(key).inserted else { return }
        Log.sidebar.notice("Leaving \(key, privacy: .public) over the bar: it \(reason, privacy: .public)")
    }

    private func forget(_ identity: ApplicationIdentity) {
        let prefix = "\(identity.bundleIdentifier)#"
        attempts = attempts.filter { !$0.key.hasPrefix(prefix) }
        blocked = blocked.filter { !$0.hasPrefix(prefix) }
    }

    private func setObserving(_ observing: Bool) {
        guard observing != isObserving else { return }
        isObserving = observing
        observeGeometry?(observing)
        Log.sidebar.notice("Reserved space \(observing ? "on" : "off", privacy: .public)")
    }

    static func regularApplications() -> [ApplicationIdentity] {
        let own = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { running in
            guard running.activationPolicy == .regular,
                  running.processIdentifier != own,
                  let bundleIdentifier = running.bundleIdentifier
            else { return nil }
            return ApplicationIdentity(
                bundleIdentifier: bundleIdentifier,
                processIdentifier: running.processIdentifier
            )
        }
    }
}
