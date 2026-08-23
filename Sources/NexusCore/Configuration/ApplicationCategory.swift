import Foundation
import AppKit

/// Group names come from what applications already declare about themselves:
/// `LSApplicationCategoryType` in the bundle's `Info.plist` — `public.app-category.social`,
/// `public.app-category.developer-tools`, and so on. LaunchServices supplies it for free from the
/// bundle Nexus already opens for the icon, so naming a group costs nothing extra (M13).
public enum ApplicationCategory {
    public static let fallbackName = "Group"

    /// Names that read better than the identifier's own words.
    private static let overrides: [String: String] = [
        "developer-tools": "Developer",
        "graphics-design": "Design",
        "healthcare-fitness": "Health",
        "social-networking": "Social",
        "photography": "Photos",
        "video": "Video",
        "music": "Music",
        "productivity": "Productivity",
        "utilities": "Utilities",
    ]

    /// `public.app-category.developer-tools` → `Developer`. Anything unrecognised is title-cased
    /// from its own last component, so a category Apple adds tomorrow still reads as a word.
    public static func displayName(for identifier: String) -> String? {
        let prefix = "public.app-category."
        guard identifier.hasPrefix(prefix) else { return nil }
        // Sub-categories exist (`public.app-category.action-games`); the leaf is the specific one.
        let slug = String(identifier.dropFirst(prefix.count))
        guard !slug.isEmpty else { return nil }
        if let override = overrides[slug] { return override }
        return slug
            .split(separator: "-")
            .map(\.capitalized)
            .joined(separator: " ")
    }

    /// Reads `LSApplicationCategoryType` from a bundle. `nil` for an application that declares
    /// none, which plenty of older ones do.
    public static func category(of bundleURL: URL) -> String? {
        Bundle(url: bundleURL)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
    }

    /// The name for a group of applications: the category shared by most of them, or `Group` when
    /// they have nothing in common — including when none of them declares a category at all.
    ///
    /// "Most" means a plurality, not a majority: two Developer applications and one Social one is
    /// a Developer group. Ties go to the first category in member order, so the name does not
    /// depend on dictionary iteration.
    public static func groupName(for categories: [String?]) -> String {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for case let category? in categories {
            guard let name = displayName(for: category) else { continue }
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        var best: String?
        var bestCount = 0
        for name in order where (counts[name] ?? 0) > bestCount {
            best = name
            bestCount = counts[name] ?? 0
        }
        return best ?? fallbackName
    }
}
