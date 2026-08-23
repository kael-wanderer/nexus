import Foundation
import Testing

@testable import NexusCore

private struct StubProvider: SearchProvider {
    let identifier: SearchProviderID
    let category: SearchCategory
    var debounce: Duration = .zero
    var minimumCharacters = 1
    var delay: Duration = .zero
    var titles: [String] = []
    var hangs = false

    func results(for query: SearchQuery, context: SearchContext) async -> [SearchResult] {
        if hangs {
            try? await Task.sleep(for: .seconds(30))
            return []
        }
        if delay > .zero { try? await Task.sleep(for: delay) }
        return titles.enumerated().compactMap { index, title in
            guard let matchScore = StringMatch.score(query: query.trimmed, candidate: title)
            else { return nil }
            return SearchResult(
                id: "\(identifier.rawValue):\(index)",
                title: title,
                icon: .symbol("circle"),
                category: category,
                score: Ranking.score(
                    matchScore: matchScore,
                    category: category,
                    frecencyBoost: context.frecency.boost(for: "\(identifier.rawValue):\(index)", now: context.now),
                    isRunning: false,
                    belongsToFrontmostApplication: false
                ),
                action: .runBuiltInAction(.openHome)
            )
        }
    }
}

private func collect(_ stream: AsyncStream<SearchSnapshot>) async -> [SearchSnapshot] {
    var snapshots: [SearchSnapshot] = []
    for await snapshot in stream { snapshots.append(snapshot) }
    return snapshots
}

@Suite("SearchEngine")
struct SearchEngineTests {
    private let context = SearchContext()

    @Test("Every provider's results are merged into the final snapshot")
    func fanOut() async {
        let engine = SearchEngine(providers: [
            StubProvider(identifier: .application, category: .application, titles: ["Code"]),
            StubProvider(identifier: .action, category: .action, titles: ["Code Review"]),
        ])
        let snapshots = await collect(engine.search(SearchQuery(text: "code", token: 1), context: context))

        #expect(snapshots.count == 2)
        #expect(snapshots.last?.isComplete == true)
        #expect(snapshots.last?.results.count == 2)
        #expect(snapshots.last?.results.first?.title == "Code")
    }

    @Test("A fast provider delivers before a slow one, progressively")
    func progressive() async {
        let engine = SearchEngine(providers: [
            StubProvider(identifier: .application, category: .application, titles: ["Code"]),
            StubProvider(
                identifier: .file,
                category: .file,
                delay: .milliseconds(120),
                titles: ["code.swift"]
            ),
        ])
        let snapshots = await collect(engine.search(SearchQuery(text: "code", token: 1), context: context))

        #expect(snapshots.count == 2)
        #expect(snapshots[0].results.map(\.category) == [.application])
        #expect(snapshots[0].isComplete == false)
        #expect(snapshots[1].results.count == 2)
        #expect(snapshots[1].isComplete)
    }

    @Test("A hanging provider does not stop the others from delivering")
    func hangingProvider() async {
        let engine = SearchEngine(providers: [
            StubProvider(identifier: .application, category: .application, titles: ["Code"]),
            StubProvider(identifier: .file, category: .file, hangs: true),
        ])
        let stream = await engine.search(SearchQuery(text: "code", token: 1), context: context)

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.results.count == 1)
        #expect(first?.isComplete == false)
        await engine.cancelAll()
    }

    @Test("A superseded query's work is cancelled")
    func cancellation() async {
        let engine = SearchEngine(providers: [
            StubProvider(
                identifier: .file,
                category: .file,
                delay: .milliseconds(400),
                titles: ["code.swift"]
            )
        ])
        let first = await engine.search(SearchQuery(text: "co", token: 1), context: context)
        _ = first   // never iterated; superseded below

        let second = await engine.search(SearchQuery(text: "code", token: 2), context: context)
        let snapshots = await collect(second)
        #expect(snapshots.allSatisfy { $0.token == 2 })
    }

    @Test("Providers below their minimum character count are skipped")
    func minimumCharacters() async {
        let engine = SearchEngine(providers: [
            StubProvider(identifier: .application, category: .application, titles: ["Code"]),
            StubProvider(
                identifier: .file,
                category: .file,
                minimumCharacters: 2,
                titles: ["c.swift"]
            ),
        ])
        let snapshots = await collect(engine.search(SearchQuery(text: "c", token: 1), context: context))
        #expect(snapshots.count == 1)
        #expect(snapshots.last?.results.allSatisfy { $0.category == .application } == true)
    }

    @Test("Disabled providers contribute nothing")
    func disabledProvider() async {
        let engine = SearchEngine(
            providers: [
                StubProvider(identifier: .application, category: .application, titles: ["Code"]),
                StubProvider(identifier: .file, category: .file, titles: ["code.swift"]),
            ],
            enabled: [.application]
        )
        let snapshots = await collect(engine.search(SearchQuery(text: "code", token: 1), context: context))
        #expect(snapshots.last?.results.count == 1)
    }

    @Test("An empty query yields one empty, complete snapshot")
    func emptyQuery() async {
        let engine = SearchEngine(providers: [
            StubProvider(identifier: .application, category: .application, titles: ["Code"])
        ])
        let snapshots = await collect(engine.search(SearchQuery(text: "   ", token: 1), context: context))
        #expect(snapshots.count == 1)
        #expect(snapshots[0].results.isEmpty)
        #expect(snapshots[0].isComplete)
    }

    @Test("The configured maximum is respected")
    func maximumResults() async {
        let titles = (0..<30).map { "Code \($0)" }
        let engine = SearchEngine(
            providers: [StubProvider(identifier: .application, category: .application, titles: titles)],
            maximumResults: 3
        )
        let snapshots = await collect(engine.search(SearchQuery(text: "code", token: 1), context: context))
        #expect(snapshots.last?.results.count == 3)
    }

    @Test("Frecency lifts a previously used result above an equal match")
    func frecencyOrdering() async {
        var frecency = Frecency()
        for _ in 0..<10 { frecency.record("application:1") }
        let engine = SearchEngine(providers: [
            StubProvider(identifier: .application, category: .application, titles: ["Code A", "Code B"])
        ])
        let snapshots = await collect(
            engine.search(
                SearchQuery(text: "code", token: 1),
                context: SearchContext(frecency: frecency)
            )
        )
        #expect(snapshots.last?.results.first?.id == "application:1")
    }
}

@Suite("Search providers")
struct ProviderTests {
    @Test("The application provider matches on name and flags running applications")
    func applicationProvider() async {
        let snapshot = ApplicationIndexSnapshot()
        snapshot.write([
            NexusApplication(
                identity: ApplicationIdentity(bundleIdentifier: "com.microsoft.VSCode"),
                name: "Visual Studio Code",
                bundleURL: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
            ),
            NexusApplication(
                identity: ApplicationIdentity(bundleIdentifier: "com.apple.Safari"),
                name: "Safari",
                bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
            ),
        ])
        let provider = ApplicationSearchProvider(
            index: snapshot,
            runningBundleIdentifiers: { ["com.apple.Safari"] }
        )
        let results = await provider.results(
            for: SearchQuery(text: "code", token: 1),
            context: SearchContext()
        )
        #expect(results.count == 1)
        #expect(results[0].title == "Visual Studio Code")
        #expect(results[0].action == .launchApplication("com.microsoft.VSCode"))

        let safari = await provider.results(
            for: SearchQuery(text: "safari", token: 2),
            context: SearchContext()
        )
        #expect(safari.first?.isRunning == true)
    }

    @Test("The window provider matches titles and the app-plus-title label")
    func windowProvider() async {
        let window = NexusWindow(
            identity: WindowIdentity(
                owner: ApplicationIdentity(bundleIdentifier: "com.microsoft.VSCode"),
                number: 7
            ),
            title: "Bugler",
            applicationName: "Code"
        )
        let provider = WindowSearchProvider(windows: { [window] })

        let byTitle = await provider.results(for: SearchQuery(text: "bugler", token: 1), context: SearchContext())
        #expect(byTitle.count == 1)
        #expect(byTitle[0].action == .activateWindow(window.identity))

        let byApplication = await provider.results(for: SearchQuery(text: "code", token: 2), context: SearchContext())
        #expect(byApplication.count == 1)

        let noMatch = await provider.results(for: SearchQuery(text: "zzzz", token: 3), context: SearchContext())
        #expect(noMatch.isEmpty)
    }

    @Test("The window provider declares Accessibility and yields nothing without windows")
    func windowProviderPermission() async {
        let provider = WindowSearchProvider(windows: { [] })
        #expect(provider.requiredPermission == .accessibility)
        let results = await provider.results(for: SearchQuery(text: "any", token: 1), context: SearchContext())
        #expect(results.isEmpty)
    }

    @Test("The file provider is the only debounced one and needs two characters")
    func fileProviderShape() {
        let provider = FileSearchProvider(run: { _, _, _ in [] })
        #expect(provider.debounce == .milliseconds(120))
        #expect(provider.minimumCharacters == 2)
        #expect(provider.requiredPermission == nil)
    }

    @Test("File results carry an open action and a tilde-shortened subtitle")
    func fileProvider() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("Projects/Bugler.swift")
        let provider = FileSearchProvider(run: { _, _, _ in
            [MetadataItem(url: url, displayName: "Bugler.swift")]
        })
        let results = await provider.results(
            for: SearchQuery(text: "bugler.swift", token: 1),
            context: SearchContext()
        )
        #expect(results.count == 1)
        #expect(results[0].action == .openFile(url))
        #expect(results[0].subtitle?.hasPrefix("~") == true)
    }

    @Test("The action provider offers the built-ins plus a Quit for each running application")
    func actionProvider() async {
        let provider = ActionSearchProvider(
            runningApplications: { [(name: "Safari", bundleIdentifier: "com.apple.Safari")] }
        )
        let quit = await provider.results(for: SearchQuery(text: "quit safari", token: 1), context: SearchContext())
        #expect(quit.first?.action == .quitApplication("com.apple.Safari"))

        let terminal = await provider.results(for: SearchQuery(text: "open terminal", token: 2), context: SearchContext())
        #expect(terminal.first?.action == .runBuiltInAction(.openTerminal))

        let lock = await provider.results(for: SearchQuery(text: "lock", token: 3), context: SearchContext())
        #expect(lock.contains { $0.action == .runBuiltInAction(.lockScreen) })
    }
}
