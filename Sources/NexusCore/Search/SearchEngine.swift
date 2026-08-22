import Foundation

/// Progressive delivery, not one final answer: in-memory providers emit a first snapshot within
/// a few milliseconds and the file provider merges in later (DESIGN_MVP §4.1).
public actor SearchEngine {
    private let providers: [any SearchProvider]
    private var enabled: Set<SearchProviderID>
    private var maximumResults: Int
    private var running: [UInt64: Task<Void, Never>] = [:]

    public init(
        providers: [any SearchProvider],
        enabled: Set<SearchProviderID> = Set(SearchProviderID.allCases),
        maximumResults: Int = 20
    ) {
        self.providers = providers
        self.enabled = enabled
        self.maximumResults = maximumResults
    }

    public func configure(enabled: Set<SearchProviderID>, maximumResults: Int) {
        self.enabled = enabled
        self.maximumResults = max(1, maximumResults)
    }

    public func cancelAll() {
        for task in running.values { task.cancel() }
        running.removeAll()
    }

    /// Each call supersedes the previous one. The returned stream finishes when every provider
    /// has reported or the query is superseded.
    public func search(_ query: SearchQuery, context: SearchContext) -> AsyncStream<SearchSnapshot> {
        cancelAll()

        let active = providers.filter {
            enabled.contains($0.identifier) && query.trimmed.count >= $0.minimumCharacters
        }
        let maximumResults = self.maximumResults

        return AsyncStream { continuation in
            guard !active.isEmpty, !query.isEmpty else {
                continuation.yield(SearchSnapshot(token: query.token, results: [], isComplete: true))
                continuation.finish()
                return
            }

            let task = Task {
                let signpost = Log.signposter.beginInterval("search")
                defer { Log.signposter.endInterval("search", signpost) }

                var merged: [SearchProviderID: [SearchResult]] = [:]
                var remaining = active.count

                await withTaskGroup(of: (SearchProviderID, [SearchResult]).self) { group in
                    for provider in active {
                        group.addTask {
                            if provider.debounce > .zero {
                                try? await Task.sleep(for: provider.debounce)
                                if Task.isCancelled { return (provider.identifier, []) }
                            }
                            return (provider.identifier, await provider.results(for: query, context: context))
                        }
                    }
                    for await (identifier, results) in group {
                        if Task.isCancelled { break }
                        merged[identifier] = results
                        remaining -= 1
                        continuation.yield(
                            SearchSnapshot(
                                token: query.token,
                                results: Ranking.capped(
                                    merged.values.flatMap(\.self),
                                    maximumTotal: maximumResults
                                ),
                                isComplete: remaining == 0
                            )
                        )
                    }
                }
                continuation.finish()
            }

            running[query.token] = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
