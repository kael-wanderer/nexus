import AppKit
import Foundation

/// Bounded cache of application icons. `NSImage` is not `Sendable`, so the whole cache is
/// main-actor confined — which is also where every consumer (SwiftUI) lives.
@MainActor
public final class IconCache {
    public static let shared = IconCache()

    private let cache = NSCache<NSString, NSImage>()

    public init(countLimit: Int = 256) {
        cache.countLimit = countLimit
    }

    public func icon(for url: URL, size: CGFloat) -> NSImage {
        let key = "\(url.path)#\(Int(size.rounded()))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        cache.setObject(icon, forKey: key)
        return icon
    }

    public func removeAll() {
        cache.removeAllObjects()
    }
}
