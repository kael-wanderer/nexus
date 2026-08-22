import AppKit
import Foundation

/// Bounded cache of application icons. `NSImage` is not `Sendable`, so the whole cache is
/// main-actor confined — which is also where every consumer (SwiftUI) lives.
@MainActor
public final class IconCache {
    public static let shared = IconCache()

    private let cache = NSCache<NSString, NSImage>()

    public init(countLimit: Int = 256, totalCostLimit: Int = 16 * 1_024 * 1_024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    public func icon(for url: URL, size: CGFloat) -> NSImage {
        let key = "\(url.path)#\(Int(size.rounded()))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        // Four bytes per pixel at the icon's backing scale; enough for the cost limit to mean
        // something without measuring the real bitmap.
        let cost = Int(size * size * 4)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    public func removeAll() {
        cache.removeAllObjects()
    }
}
