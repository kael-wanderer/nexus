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
        let isCalendar = Bundle(url: url)?.bundleIdentifier == "com.apple.iCal"
        let dayKey = isCalendar ? "#\(Self.localDayKey())" : ""
        let key = "\(url.path)#\(Int(size.rounded()))\(dayKey)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon: NSImage
        if isCalendar {
            // Unlike the Dock, NSWorkspace returns Calendar's generic full-month asset. The Dock
            // composes its compact weekday/date face itself, so Nexus does the same special case.
            icon = Self.calendarIcon(size: size)
        } else {
            icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: size, height: size)
        }
        // Four bytes per pixel at the icon's backing scale; enough for the cost limit to mean
        // something without measuring the real bitmap.
        let cost = Int(size * size * 4)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    public func removeAll() {
        cache.removeAllObjects()
    }

    private static func localDayKey(now: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: now)
        return "\(parts.era ?? 0)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private static func calendarIcon(
        size: CGFloat,
        now: Date = Date(),
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> NSImage {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        let weekday = formatter.string(from: now)
        formatter.setLocalizedDateFormatFromTemplate("d")
        let day = formatter.string(from: now)

        return NSImage(size: NSSize(width: size, height: size), flipped: false) { bounds in
            NSGraphicsContext.current?.imageInterpolation = .high

            let face = bounds.insetBy(dx: size * 0.045, dy: size * 0.045)
            let path = NSBezierPath(
                roundedRect: face,
                xRadius: size * 0.22,
                yRadius: size * 0.22
            )
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = max(1, size * 0.035)
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.018)
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            NSColor.white.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byClipping

            (weekday as NSString).draw(
                in: NSRect(x: 0, y: size * 0.66, width: size, height: size * 0.23),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: size * 0.205, weight: .semibold),
                    .foregroundColor: NSColor.systemRed,
                    .paragraphStyle: paragraph,
                ]
            )
            (day as NSString).draw(
                in: NSRect(x: 0, y: size * 0.13, width: size, height: size * 0.56),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: size * 0.55, weight: .light),
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: paragraph,
                ]
            )
            return true
        }
    }
}
