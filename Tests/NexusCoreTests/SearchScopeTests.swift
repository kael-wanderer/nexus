import Foundation
import Testing

@testable import NexusCore

@Suite("Search scope")
struct SearchScopeTests {
    @Test("Everything runs every provider; each other scope runs fewer")
    func providers() {
        #expect(SearchScope.everything.providers == Set(SearchProviderID.allCases))
        for scope in SearchScope.allCases where scope != .everything {
            #expect(scope.providers.count < SearchProviderID.allCases.count)
            #expect(!scope.providers.isEmpty)
        }
    }

    @Test("Applications, files and settings each reach exactly one provider")
    func providerMapping() {
        #expect(SearchScope.applications.providers == [.application])
        #expect(SearchScope.filesAndFolders.providers == [.file])
        #expect(SearchScope.files.providers == [.file])
        #expect(SearchScope.folders.providers == [.file])
        #expect(SearchScope.settings.providers == [.action])
    }

    @Test("Files and folders are complements over the same provider")
    func fileKinds() {
        #expect(SearchScope.files.fileKind == .filesOnly)
        #expect(SearchScope.folders.fileKind == .foldersOnly)
        #expect(SearchScope.filesAndFolders.fileKind == .any)
        #expect(SearchScope.everything.fileKind == .any)
    }

    @Test("⌃1…⌃6 map to the scopes, and nothing else does")
    func shortcuts() {
        #expect(SearchScope.scope(forShortcut: 1) == .everything)
        #expect(SearchScope.scope(forShortcut: 6) == .settings)
        #expect(SearchScope.scope(forShortcut: 0) == nil)
        #expect(SearchScope.scope(forShortcut: 7) == nil)
        for scope in SearchScope.allCases {
            #expect(SearchScope.scope(forShortcut: scope.shortcut) == scope)
        }
    }

    @Test("Tab wraps in both directions")
    func cycling() {
        #expect(SearchScope.everything.cycled(by: -1) == .settings)
        #expect(SearchScope.settings.cycled(by: 1) == .everything)
        var scope = SearchScope.everything
        for _ in SearchScope.allCases { scope = scope.cycled(by: 1) }
        #expect(scope == .everything)
    }

    @Test("A folders query asks Spotlight for folders, and a files query asks for everything else")
    func predicates() {
        #expect(FileKind.any.predicate == nil)
        let folders = MetadataSearch.displayNamePrefix("work", kind: .foldersOnly).predicate
        let files = MetadataSearch.displayNamePrefix("work", kind: .filesOnly).predicate
        let both = MetadataSearch.displayNamePrefix("work", kind: .any).predicate

        #expect(folders.predicateFormat.contains("public.folder"))
        #expect(files.predicateFormat.contains("public.folder"))
        // The complement is a NOT over the same clause, not a different clause.
        #expect(files.predicateFormat.contains("NOT"))
        #expect(!folders.predicateFormat.contains("NOT"))
        // Both narrow the same name query rather than replacing it.
        for predicate in [folders, files, both] {
            #expect(predicate.predicateFormat.contains("kMDItemDisplayName"))
        }
        #expect(!both.predicateFormat.contains("public.folder"))
    }

    @Test("A scope narrows which providers run, and everything runs them all")
    func engineRespectsScope() async {
        let engine = SearchEngine(providers: [
            CountingProvider(identifier: .application, category: .application),
            CountingProvider(identifier: .file, category: .file),
            CountingProvider(identifier: .action, category: .action),
        ])

        let everything = await collect(engine, scope: .everything)
        #expect(Set(everything.map(\.category)) == [.application, .file, .action])

        let applications = await collect(engine, scope: .applications)
        #expect(Set(applications.map(\.category)) == [.application])

        let settings = await collect(engine, scope: .settings)
        #expect(Set(settings.map(\.category)) == [.action])
    }

    @Test("The file provider passes the scope's kind down to the query")
    func fileProviderPassesKind() async {
        let box = KindBox()
        let provider = FileSearchProvider(run: { _, _, kind in
            await box.record(kind)
            return []
        })
        _ = await provider.results(
            for: SearchQuery(text: "notes", token: 1, scope: .folders),
            context: SearchContext()
        )
        #expect(await box.kinds == [.foldersOnly])
    }

    private func collect(_ engine: SearchEngine, scope: SearchScope) async -> [SearchResult] {
        var results: [SearchResult] = []
        for await snapshot in await engine.search(
            SearchQuery(text: "anything", token: UInt64(scope.shortcut), scope: scope),
            context: SearchContext()
        ) {
            results = snapshot.results
        }
        return results
    }
}

/// Answers one result of its own category, so a snapshot names the providers that ran.
private struct CountingProvider: SearchProvider {
    let identifier: SearchProviderID
    let category: SearchCategory

    func results(for query: SearchQuery, context: SearchContext) async -> [SearchResult] {
        [
            SearchResult(
                id: "\(identifier.rawValue):1",
                title: identifier.rawValue,
                icon: .symbol("circle"),
                category: category,
                score: 0.5,
                action: .runBuiltInAction(.openHome)
            )
        ]
    }
}

private actor KindBox {
    var kinds: [FileKind] = []
    func record(_ kind: FileKind) { kinds.append(kind) }
}
