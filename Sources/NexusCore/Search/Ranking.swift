import Foundation

/// Frecency: how often, how recently. Also the data source for "Recent applications".
public struct Frecency: Sendable, Equatable {
    public static let halfLife: TimeInterval = 14 * 24 * 60 * 60
    public static let maximumBoost = 0.30
    /// Uses beyond this stop increasing the boost.
    public static let saturationCount = 10

    public private(set) var entries: [String: FrecencyEntry]

    public init(entries: [String: FrecencyEntry] = [:]) {
        self.entries = entries
    }

    public func boost(for id: String, now: Date = Date()) -> Double {
        guard let entry = entries[id], entry.count > 0 else { return 0 }
        let normalizedCount = min(1.0, Double(entry.count) / Double(Self.saturationCount))
        let age = max(0, now.timeIntervalSince(entry.lastUsed))
        let decay = exp(-age / Self.halfLife)
        return (Self.maximumBoost * normalizedCount * decay).clamped(to: 0...Self.maximumBoost)
    }

    public mutating func record(_ id: String, at date: Date = Date()) {
        var entry = entries[id] ?? FrecencyEntry()
        entry.count += 1
        entry.lastUsed = date
        entries[id] = entry
    }

    /// Most recently and frequently used ids first. Backs the empty-query "recents" list.
    public func recents(limit: Int, now: Date = Date()) -> [String] {
        var scored: [(id: String, boost: Double)] = []
        for id in entries.keys {
            let value = boost(for: id, now: now)
            if value > 0 { scored.append((id, value)) }
        }
        scored.sort { lhs, rhs in
            lhs.boost == rhs.boost ? lhs.id < rhs.id : lhs.boost > rhs.boost
        }
        return Array(scored.prefix(limit).map(\.id))
    }
}

/// Deterministic scoring, so tests can assert exact orderings.
public enum Ranking {
    public static func providerWeight(_ category: SearchCategory) -> Double {
        switch category {
        case .application: 1.00
        case .window: 0.95
        case .action: 0.90
        case .file: 0.70
        }
    }

    public static let runningApplicationBoost = 0.05
    public static let frontmostWindowBoost = 0.03

    /// `score = matchScore × providerWeight + frecencyBoost + stateBoost`
    public static func score(
        matchScore: Double,
        category: SearchCategory,
        frecencyBoost: Double,
        isRunning: Bool,
        belongsToFrontmostApplication: Bool
    ) -> Double {
        var score = matchScore * providerWeight(category) + frecencyBoost
        if isRunning, category == .application { score += runningApplicationBoost }
        if belongsToFrontmostApplication, category == .window { score += frontmostWindowBoost }
        return score
    }

    /// Highest score first; ties broken by shorter title, then title ascending, then id — so the
    /// order never depends on dictionary iteration or task completion order.
    public static func sorted(_ results: [SearchResult]) -> [SearchResult] {
        results.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.title.count != rhs.title.count { return lhs.title.count < rhs.title.count }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            return lhs.id < rhs.id
        }
    }

    /// Per-category caps then a global cap, applied after sorting. No category is ever entirely
    /// squeezed out by another's volume.
    public static func capped(_ results: [SearchResult], maximumTotal: Int) -> [SearchResult] {
        var perCategory: [SearchCategory: Int] = [:]
        var kept: [SearchResult] = []
        for result in sorted(results) {
            let used = perCategory[result.category] ?? 0
            guard used < result.category.resultCap else { continue }
            perCategory[result.category] = used + 1
            kept.append(result)
            if kept.count == maximumTotal { break }
        }
        return kept
    }
}
