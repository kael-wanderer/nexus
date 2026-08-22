import CoreGraphics
import Foundation
import ScreenCaptureKit

public protocol WindowPreviewing: Sendable {
    func preview(for window: WindowIdentity, maxDimension: CGFloat) async -> SendableImage?
    func invalidate(_ window: WindowIdentity) async
}

/// `CGImage` is not `Sendable`. This is the one audited place where one crosses an isolation
/// boundary: it is produced by ScreenCaptureKit, never mutated, and only read.
public struct SendableImage: @unchecked Sendable {
    public let image: CGImage
    public init(_ image: CGImage) { self.image = image }
}

/// Window thumbnails, captured lazily on hover and never on a schedule. Entirely optional: with
/// Screen Recording denied every call returns `nil` and the flyout shows titles only.
public actor WindowPreviewService: WindowPreviewing {
    private struct Entry {
        let image: SendableImage
        let capturedAt: Date
    }

    private static let timeToLive: TimeInterval = 5
    private static let maximumEntries = 32

    private var cache: [CGWindowID: Entry] = [:]
    private var inFlight: Set<CGWindowID> = []

    public init() {}

    public func invalidate(_ window: WindowIdentity) {
        cache[window.number] = nil
    }

    public func invalidateAll() {
        cache.removeAll()
    }

    public func preview(for window: WindowIdentity, maxDimension: CGFloat) async -> SendableImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }

        if let entry = cache[window.number], Date().timeIntervalSince(entry.capturedAt) < Self.timeToLive {
            return entry.image
        }
        guard !inFlight.contains(window.number) else { return cache[window.number]?.image }
        inFlight.insert(window.number)
        defer { inFlight.remove(window.number) }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let target = content.windows.first(where: { $0.windowID == window.number }) else {
                return nil
            }
            let filter = SCContentFilter(desktopIndependentWindow: target)
            let configuration = SCStreamConfiguration()
            let scale = min(
                1,
                maxDimension / max(CGFloat(target.frame.width), CGFloat(target.frame.height), 1)
            )
            configuration.width = max(1, Int(CGFloat(target.frame.width) * scale))
            configuration.height = max(1, Int(CGFloat(target.frame.height) * scale))
            configuration.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            store(SendableImage(image), for: window.number)
            return SendableImage(image)
        } catch {
            // A denial or a window that vanished mid-capture is a normal state change (§3.5),
            // never an alert.
            Log.windows.debug("Preview unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func store(_ image: SendableImage, for identifier: CGWindowID) {
        if cache.count >= Self.maximumEntries {
            let oldest = cache.min { $0.value.capturedAt < $1.value.capturedAt }?.key
            if let oldest { cache[oldest] = nil }
        }
        cache[identifier] = Entry(image: image, capturedAt: Date())
    }
}
