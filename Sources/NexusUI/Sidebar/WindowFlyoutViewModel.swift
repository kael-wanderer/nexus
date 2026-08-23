import AppKit
import CoreGraphics
import NexusCore
import SwiftUI

@MainActor
@Observable
public final class WindowFlyoutViewModel {
    public private(set) var target: ApplicationIdentity?
    public private(set) var applicationName = ""
    public private(set) var windows: [NexusWindow] = []
    public private(set) var accessibility: PermissionStatus = .denied
    public private(set) var isLoading = false
    /// Set once the user dismisses the previews offer; never shown again (§3.5).
    public private(set) var previewsOfferDismissed = false
    public private(set) var previews: [CGWindowID: NSImage] = [:]
    /// Which way the flyout lays its windows out — set from the sidebar's edge before it opens.
    /// Beside a vertical bar they stack; above or below a horizontal one they sit side by side.
    public var isVertical = true

    @ObservationIgnored private let service: any WindowServing
    @ObservationIgnored private let previewService: any WindowPreviewing
    @ObservationIgnored private let permissions: any PermissionChecking
    @ObservationIgnored private let events: EventBus
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    @ObservationIgnored public var onDismiss: (() -> Void)?
    @ObservationIgnored public var onContentChange: (() -> Void)?

    public init(
        service: any WindowServing,
        previewService: any WindowPreviewing,
        permissions: any PermissionChecking,
        events: EventBus
    ) {
        self.service = service
        self.previewService = previewService
        self.permissions = permissions
        self.events = events
        accessibility = permissions.status(of: .accessibility)
    }

    public func start() {
        // Subscribe synchronously: creating the stream inside the Task would drop any event
        // published between `start()` and the Task's first run.
        let stream = events.events()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .windowsChanged(let identity) where identity == self.target:
                    // A window that changed is a preview that is now wrong.
                    self.previews.removeAll()
                    await self.reload()
                case .applicationTerminated(let identity) where identity == self.target:
                    self.hide()
                case .permissionChanged(.accessibility, let status):
                    self.accessibility = status
                    self.previews.removeAll()
                    // reload() clears the list when the permission is gone, so a revocation
                    // never leaves stale windows on screen behind the grant prompt.
                    await self.reload()
                default:
                    continue
                }
            }
        }
    }

    public func stop() {
        eventTask?.cancel()
        eventTask = nil
    }

    public var showsPermissionRequest: Bool { accessibility != .granted }

    public var showsPreviewsOffer: Bool {
        accessibility == .granted
            && !previewsOfferDismissed
            && permissions.status(of: .screenRecording) != .granted
            && !windows.isEmpty
    }

    public func show(_ identity: ApplicationIdentity, name: String) {
        target = identity
        applicationName = name
        windows = []
        previews = [:]
        accessibility = permissions.status(of: .accessibility)
        Task { await reload() }
    }

    public func hide() {
        target = nil
        windows = []
        previews = [:]
        onDismiss?()
    }

    public func reload() async {
        guard let target else { return }
        guard accessibility == .granted else {
            windows = []
            onContentChange?()
            return
        }
        isLoading = true
        defer { isLoading = false }
        let loaded = (try? await service.windows(for: target)) ?? []
        guard self.target == target else { return }
        let changed = loaded.map(\.id) != windows.map(\.id)
        windows = loaded
        if changed { onContentChange?() }
        // The flyout opens on hover now, so every thumbnail is wanted at once — waiting for the
        // pointer to reach each row would show an empty frame for as long as it takes to get there.
        requestPreviews()
    }

    public func activate(_ window: NexusWindow) {
        Task { [service] in try? await service.activate(window.identity) }
        hide()
    }

    /// Captures every window's thumbnail, if Screen Recording allows it. Cheap to call twice: the
    /// preview service caches, and an already-loaded window is skipped.
    public func requestPreviews() {
        guard permissions.status(of: .screenRecording) == .granted else { return }
        for window in windows where previews[window.identity.number] == nil {
            requestPreview(for: window)
        }
    }

    public func requestAccessibility() {
        permissions.requestOrOpenSettings(.accessibility)
    }

    public func requestScreenRecording() {
        permissions.requestOrOpenSettings(.screenRecording)
    }

    public func dismissPreviewsOffer() {
        previewsOfferDismissed = true
        onContentChange?()
    }

    /// Previews are captured lazily on hover, never on a schedule (§3.5).
    public func requestPreview(for window: NexusWindow) {
        guard previews[window.identity.number] == nil else { return }
        Task { [previewService] in
            guard let image = await previewService.preview(for: window.identity, maxDimension: 320)
            else { return }
            previews[window.identity.number] = NSImage(
                cgImage: image.image,
                size: NSSize(width: image.image.width, height: image.image.height)
            )
            // A thumbnail makes the flyout taller (or wider). Without a re-measure the panel keeps
            // its old frame and the image is drawn outside it — captured, stored, invisible.
            onContentChange?()
        }
    }
}
