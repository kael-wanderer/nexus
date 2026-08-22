import AppKit
import NexusCore
import SwiftUI

@MainActor
@Observable
public final class SearchViewModel {
    public var query = "" {
        didSet {
            guard query != oldValue else { return }
            selectionIsPinned = false
            runSearch()
        }
    }

    public private(set) var results: [SearchResult] = []
    public private(set) var selectedID: String?
    public private(set) var isSearching = false

    @ObservationIgnored private let engine: SearchEngine
    @ObservationIgnored private let configuration: ConfigurationController
    @ObservationIgnored private let index: ApplicationIndexSnapshot
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var token: UInt64 = 0
    /// Once the user has arrowed, a later snapshot must not move the selection.
    @ObservationIgnored private var selectionIsPinned = false

    @ObservationIgnored public var onExecute: ((SearchResult, Bool) -> Void)?
    @ObservationIgnored public var onClose: (() -> Void)?
    @ObservationIgnored public var onResultsChanged: (() -> Void)?
    @ObservationIgnored public var frontmostApplication: (() -> String?)?

    public init(
        engine: SearchEngine,
        configuration: ConfigurationController,
        index: ApplicationIndexSnapshot
    ) {
        self.engine = engine
        self.configuration = configuration
        self.index = index
    }

    public var selectedResult: SearchResult? {
        results.first { $0.id == selectedID }
    }

    /// Category headers, in a fixed order, over the already-ranked list.
    public var groupedResults: [(category: SearchCategory, results: [SearchResult])] {
        Dictionary(grouping: results, by: \.category)
            .sorted { $0.key.order < $1.key.order }
            .map { (category: $0.key, results: $0.value) }
    }

    // MARK: - Lifecycle

    public func prepareForDisplay() {
        selectionIsPinned = false
        runSearch()
    }

    public func reset() {
        searchTask?.cancel()
        searchTask = nil
        query = ""
        results = []
        selectedID = nil
        isSearching = false
    }

    // MARK: - Searching

    private func runSearch() {
        searchTask?.cancel()
        token &+= 1
        let current = SearchQuery(text: query, token: token)

        guard !current.isEmpty else {
            results = recentResults()
            selectedID = results.first?.id
            isSearching = false
            onResultsChanged?()
            return
        }

        let context = SearchContext(
            frecency: Frecency(entries: configuration.configuration.frecency),
            frontmostApplication: frontmostApplication?()
        )
        isSearching = true
        searchTask = Task { [engine, weak self] in
            for await snapshot in await engine.search(current, context: context) {
                guard let self, snapshot.token == self.token else { continue }
                self.apply(snapshot)
            }
            guard let self, current.token == self.token else { return }
            self.isSearching = false
        }
    }

    private func apply(_ snapshot: SearchSnapshot) {
        results = snapshot.results
        // File results merge in below the fast categories and must not move the selection.
        if let selectedID, results.contains(where: { $0.id == selectedID }) {
            // keep it
        } else if selectionIsPinned, !results.isEmpty {
            selectedID = results.first?.id
        } else {
            selectedID = results.first?.id
        }
        if snapshot.isComplete { isSearching = false }
        onResultsChanged?()
    }

    /// Empty query shows recent applications from frecency, not an empty box.
    private func recentResults() -> [SearchResult] {
        let frecency = Frecency(entries: configuration.configuration.frecency)
        let applications = Dictionary(
            index.read().map { ($0.identity.bundleIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return frecency.recents(limit: 8).compactMap { id in
            guard id.hasPrefix("app:") else { return nil }
            let bundleIdentifier = String(id.dropFirst(4))
            guard let application = applications[bundleIdentifier] else { return nil }
            return SearchResult(
                id: id,
                title: application.name,
                subtitle: String(localized: "Recent"),
                icon: .application(application.bundleURL),
                category: .application,
                action: .launchApplication(bundleIdentifier),
                secondaryAction: .openFile(application.bundleURL)
            )
        }
    }

    // MARK: - Keyboard

    public func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectionIsPinned = true
        let currentIndex = results.firstIndex { $0.id == selectedID } ?? 0
        let next = (currentIndex + delta).clamped(to: 0...(results.count - 1))
        selectedID = results[next].id
    }

    public func select(_ result: SearchResult) {
        selectionIsPinned = true
        selectedID = result.id
    }

    public func selectRow(_ index: Int) {
        guard results.indices.contains(index) else { return }
        selectionIsPinned = true
        selectedID = results[index].id
        execute(secondary: false)
    }

    public func execute(secondary: Bool) {
        guard let result = selectedResult else { return }
        configuration.update { $0.frecency[result.id, default: FrecencyEntry()].bump() }
        onExecute?(result, secondary)
    }

    public func close() {
        onClose?()
    }
}

extension FrecencyEntry {
    mutating func bump(at date: Date = Date()) {
        count += 1
        lastUsed = date
    }
}
