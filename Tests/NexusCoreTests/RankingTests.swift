import Foundation
import Testing

@testable import NexusCore

private func result(
    _ id: String,
    _ title: String,
    _ category: SearchCategory,
    score: Double
) -> SearchResult {
    SearchResult(
        id: id,
        title: title,
        icon: .symbol("circle"),
        category: category,
        score: score,
        action: .runBuiltInAction(.openHome)
    )
}

@Suite("Frecency")
struct FrecencyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("An unused id gets no boost")
    func unused() {
        #expect(Frecency().boost(for: "app:x", now: now) == 0)
    }

    @Test("Boost is capped at 0.30 however often something is used")
    func cap() {
        var frecency = Frecency()
        for _ in 0..<1_000 { frecency.record("app:x", at: now) }
        #expect(frecency.boost(for: "app:x", now: now) == Frecency.maximumBoost)
    }

    @Test("Boost decays with age")
    func decay() {
        var frecency = Frecency()
        for _ in 0..<10 { frecency.record("app:x", at: now) }
        let fresh = frecency.boost(for: "app:x", now: now)
        let old = frecency.boost(for: "app:x", now: now.addingTimeInterval(Frecency.halfLife))
        let ancient = frecency.boost(for: "app:x", now: now.addingTimeInterval(Frecency.halfLife * 10))
        #expect(fresh > old)
        #expect(old > ancient)
        #expect(ancient >= 0)
    }

    @Test("More uses beat fewer uses at the same moment")
    func count() {
        var frecency = Frecency()
        for _ in 0..<5 { frecency.record("app:many", at: now) }
        frecency.record("app:few", at: now)
        #expect(frecency.boost(for: "app:many", now: now) > frecency.boost(for: "app:few", now: now))
    }

    @Test("Recents are ordered by boost, ties broken deterministically")
    func recents() {
        var frecency = Frecency()
        for _ in 0..<5 { frecency.record("app:b", at: now) }
        for _ in 0..<3 { frecency.record("app:a", at: now) }
        for _ in 0..<3 { frecency.record("app:c", at: now) }
        #expect(frecency.recents(limit: 3, now: now) == ["app:b", "app:a", "app:c"])
        #expect(frecency.recents(limit: 1, now: now) == ["app:b"])
    }
}

@Suite("Ranking")
struct RankingTests {
    @Test("Provider weights match the design exactly")
    func weights() {
        #expect(Ranking.providerWeight(.application) == 1.00)
        #expect(Ranking.providerWeight(.window) == 0.95)
        #expect(Ranking.providerWeight(.action) == 0.90)
        #expect(Ranking.providerWeight(.file) == 0.70)
    }

    @Test("An identical match ranks an application above a file")
    func categoryOrdering() {
        let application = Ranking.score(
            matchScore: 0.9, category: .application, frecencyBoost: 0,
            isRunning: false, belongsToFrontmostApplication: false
        )
        let file = Ranking.score(
            matchScore: 0.9, category: .file, frecencyBoost: 0,
            isRunning: false, belongsToFrontmostApplication: false
        )
        #expect(application > file)
    }

    @Test("State boosts apply only to the category they describe")
    func stateBoosts() {
        let running = Ranking.score(
            matchScore: 0.5, category: .application, frecencyBoost: 0,
            isRunning: true, belongsToFrontmostApplication: false
        )
        let stopped = Ranking.score(
            matchScore: 0.5, category: .application, frecencyBoost: 0,
            isRunning: false, belongsToFrontmostApplication: false
        )
        #expect(abs(running - stopped - Ranking.runningApplicationBoost) < 1e-12)

        // A "running" file makes no sense and must not be boosted.
        let file = Ranking.score(
            matchScore: 0.5, category: .file, frecencyBoost: 0,
            isRunning: true, belongsToFrontmostApplication: true
        )
        #expect(file == 0.5 * 0.70)
    }

    @Test("A window of the frontmost application gets its own small boost")
    func frontmostWindow() {
        let front = Ranking.score(
            matchScore: 0.5, category: .window, frecencyBoost: 0,
            isRunning: true, belongsToFrontmostApplication: true
        )
        let other = Ranking.score(
            matchScore: 0.5, category: .window, frecencyBoost: 0,
            isRunning: true, belongsToFrontmostApplication: false
        )
        #expect(abs(front - other - Ranking.frontmostWindowBoost) < 1e-12)
    }

    @Test("Sorting is fully deterministic: score, then title length, then title, then id")
    func deterministicSort() {
        let input = [
            result("c", "Bbb", .application, score: 0.5),
            result("a", "Aaaa", .application, score: 0.5),
            result("b", "Bbb", .application, score: 0.5),
            result("d", "Zed", .application, score: 0.9),
        ]
        #expect(Ranking.sorted(input).map(\.id) == ["d", "b", "c", "a"])
        // Same input in a different order produces the same output.
        #expect(Ranking.sorted(input.reversed()).map(\.id) == ["d", "b", "c", "a"])
    }

    @Test("Per-category caps stop one category from crowding out another")
    func caps() {
        var input: [SearchResult] = []
        for index in 0..<40 {
            input.append(result("f\(index)", "File \(index)", .file, score: 0.99))
        }
        input.append(result("app", "App", .application, score: 0.10))

        let capped = Ranking.capped(input, maximumTotal: 20)
        #expect(capped.filter { $0.category == .file }.count == SearchCategory.file.resultCap)
        #expect(capped.contains { $0.id == "app" })
    }

    @Test("The global cap is honoured after the per-category caps")
    func globalCap() {
        var input: [SearchResult] = []
        for index in 0..<20 { input.append(result("a\(index)", "App \(index)", .application, score: 0.9)) }
        for index in 0..<20 { input.append(result("w\(index)", "Win \(index)", .window, score: 0.9)) }
        for index in 0..<20 { input.append(result("c\(index)", "Act \(index)", .action, score: 0.9)) }
        for index in 0..<20 { input.append(result("f\(index)", "Fil \(index)", .file, score: 0.9)) }

        #expect(Ranking.capped(input, maximumTotal: 20).count == 20)
        #expect(Ranking.capped(input, maximumTotal: 5).count == 5)
        // 8 + 8 + 5 + 6 = 27 category slots, so a cap of 27 keeps them all.
        #expect(Ranking.capped(input, maximumTotal: 100).count == 27)
    }

    @Test("An empty input produces an empty output, not a crash")
    func emptyInput() {
        #expect(Ranking.capped([], maximumTotal: 20).isEmpty)
        #expect(Ranking.sorted([]).isEmpty)
    }
}
