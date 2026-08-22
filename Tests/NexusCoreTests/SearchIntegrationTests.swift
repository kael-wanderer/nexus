import Foundation
import Testing

@testable import NexusCore

/// End-to-end against the real machine: the real Spotlight index, the real application
/// catalogue. These are the ROADMAP Milestone 5 acceptance criteria that can be checked without
/// a human at the keyboard.
@Suite("Search integration", .serialized)
struct SearchIntegrationTests {
    @MainActor
    private func buildIndex() async -> ApplicationIndexSnapshot {
        let index = ApplicationIndex(events: EventBus())
        index.ensureBuilt()
        // The build runs on a detached task; wait for it to land.
        for _ in 0..<60 where index.snapshot.read().isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return index.snapshot
    }

    @Test("The application index finds applications on this machine")
    @MainActor
    func indexBuilds() async {
        let snapshot = await buildIndex()
        #expect(snapshot.read().count > 10)
        #expect(snapshot.read().contains { $0.identity.bundleIdentifier == "com.apple.Safari" })
    }

    @Test("Typing an application name puts that application first")
    @MainActor
    func applicationSearchRanksCorrectly() async {
        let snapshot = await buildIndex()
        let engine = SearchEngine(
            providers: [
                ApplicationSearchProvider(index: snapshot, runningBundleIdentifiers: { [] })
            ],
            enabled: [.application]
        )
        var last: SearchSnapshot?
        for await result in await engine.search(SearchQuery(text: "safari", token: 1), context: SearchContext()) {
            last = result
        }
        #expect(last?.results.first?.title == "Safari")
        #expect(last?.results.first?.action == .launchApplication("com.apple.Safari"))
    }

    @Test("An acronym reaches a multi-word application name")
    @MainActor
    func acronymSearch() async {
        let snapshot = await buildIndex()
        let multiWord = snapshot.read().first { StringMatch.words(in: $0.name).count >= 2 }
        guard let multiWord else { return }
        let initials = String(StringMatch.words(in: multiWord.name).compactMap(\.first))

        let provider = ApplicationSearchProvider(index: snapshot, runningBundleIdentifiers: { [] })
        let results = await provider.results(
            for: SearchQuery(text: initials, token: 1),
            context: SearchContext()
        )
        #expect(results.contains { $0.title == multiWord.name })
    }

    @Test("File search returns results from the user's home through Spotlight")
    @MainActor
    func fileSearch() async {
        let provider = FileSearchProvider()
        let results = await provider.results(
            for: SearchQuery(text: "Desktop", token: 1),
            context: SearchContext()
        )
        // Spotlight can legitimately be disabled on a machine; that degrades to nothing (§11),
        // it is not a failure of Nexus.
        if results.isEmpty {
            Log.search.info("Spotlight returned nothing for the file-search integration check")
            return
        }
        #expect(results.allSatisfy { $0.category == .file })
        #expect(results.allSatisfy { if case .openFile = $0.action { true } else { false } })
    }

    @Test("Application and window results render inside the 50 ms budget")
    @MainActor
    func latencyBudget() async {
        let snapshot = await buildIndex()
        let windows = (0..<200).map { index in
            NexusWindow(
                identity: WindowIdentity(
                    owner: ApplicationIdentity(bundleIdentifier: "com.example.app\(index)"),
                    number: UInt32(index)
                ),
                title: "Document \(index)",
                applicationName: "App \(index)"
            )
        }
        let engine = SearchEngine(
            providers: [
                ApplicationSearchProvider(index: snapshot, runningBundleIdentifiers: { [] }),
                WindowSearchProvider(windows: { windows }),
            ],
            enabled: [.application, .window]
        )

        let start = ContinuousClock.now
        var last: SearchSnapshot?
        for await result in await engine.search(SearchQuery(text: "doc", token: 1), context: SearchContext()) {
            last = result
        }
        let elapsed = ContinuousClock.now - start

        #expect(last != nil)
        #expect(elapsed < .milliseconds(50), "app+window search took \(elapsed)")
    }
}
