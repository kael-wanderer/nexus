import Foundation
import NexusCore
import Testing

@testable import NexusUI

/// A provider whose answer can be delayed, so snapshot arrival order is controllable.
private struct DelayedProvider: SearchProvider {
    let identifier: SearchProviderID
    let category: SearchCategory
    var delay: Duration = .zero
    var titles: [String] = []
    var score: Double = 0.5

    func results(for query: SearchQuery, context: SearchContext) async -> [SearchResult] {
        if delay > .zero { try? await Task.sleep(for: delay) }
        return titles.enumerated().map { index, title in
            SearchResult(
                id: "\(identifier.rawValue):\(index)",
                title: title,
                icon: .symbol("circle"),
                category: category,
                score: score,
                action: .runBuiltInAction(.openHome)
            )
        }
    }
}

@MainActor
private func makeSearch(_ providers: [any SearchProvider]) -> SearchViewModel {
    SearchViewModel(
        engine: SearchEngine(providers: providers),
        configuration: ConfigurationController(
            store: InMemoryConfigurationStore(),
            events: EventBus(),
            saveDelay: .zero
        ),
        index: ApplicationIndexSnapshot()
    )
}

@Suite("Search selection stability")
@MainActor
struct SearchSelectionTests {
    /// The user-review bug: a slow provider's results merged in above the fast provider's, and
    /// the selection stayed stranded on the row it had originally landed on.
    @Test("A late, higher-ranked snapshot moves the selection back to row 0")
    func lateHigherRankedResultTakesSelection() async throws {
        let model = makeSearch([
            DelayedProvider(identifier: .window, category: .window, titles: ["a window"], score: 0.50),
            DelayedProvider(
                identifier: .application,
                category: .application,
                delay: .milliseconds(80),
                titles: ["An App"],
                score: 0.95
            ),
        ])
        model.query = "a"
        try await Task.sleep(for: .milliseconds(400))

        #expect(model.results.first?.category == .application)
        #expect(model.selectedID == model.results.first?.id)
        #expect(model.selectedResult?.category == .application)
    }

    @Test("Row 0 is preselected on every new query")
    func rowZeroPreselected() async throws {
        let model = makeSearch([
            DelayedProvider(identifier: .application, category: .application, titles: ["One", "Two"], score: 0.9)
        ])
        model.query = "o"
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.selectedID == model.results.first?.id)

        model.moveSelection(by: 1)
        #expect(model.selectedID == model.results[1].id)

        // A brand new query resets the pin, so row 0 wins again.
        model.query = "on"
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.selectedID == model.results.first?.id)
    }

    @Test("Once the user arrows, a later snapshot leaves the selection alone")
    func keyboardSelectionSurvivesLaterSnapshot() async throws {
        let model = makeSearch([
            DelayedProvider(identifier: .application, category: .application, titles: ["One", "Two"], score: 0.95),
            DelayedProvider(
                identifier: .file,
                category: .file,
                delay: .milliseconds(150),
                titles: ["a file"],
                score: 0.10
            ),
        ])
        model.query = "o"
        try await Task.sleep(for: .milliseconds(80))
        model.moveSelection(by: 1)
        let chosen = model.selectedID
        #expect(chosen == model.results[1].id)

        try await Task.sleep(for: .milliseconds(400))
        #expect(model.selectedID == chosen)
    }

    @Test("Hovering highlights a row but does not hand Return to it")
    func hoverDoesNotPinSelection() async throws {
        let model = makeSearch([
            DelayedProvider(identifier: .window, category: .window, titles: ["a window"], score: 0.50),
            DelayedProvider(
                identifier: .application,
                category: .application,
                delay: .milliseconds(80),
                titles: ["An App"],
                score: 0.95
            ),
        ])
        model.query = "a"
        try await Task.sleep(for: .milliseconds(30))

        // The palette opens under the pointer, so a row is hovered before anything is typed.
        if let hovered = model.results.first { model.select(hovered) }

        try await Task.sleep(for: .milliseconds(400))
        #expect(model.results.first?.category == .application)
        #expect(model.selectedID == model.results.first?.id)
    }

    @Test("Clicking a row pins it and executes that row")
    func clickExecutesTheClickedRow() async throws {
        let model = makeSearch([
            DelayedProvider(identifier: .application, category: .application, titles: ["One", "Two"], score: 0.9)
        ])
        var executed: SearchResult?
        model.onExecute = { result, _ in executed = result }
        model.query = "o"
        try await Task.sleep(for: .milliseconds(200))

        model.click(model.results[1])
        #expect(executed?.id == model.results[1].id)
    }

    @Test("Enter with no results does nothing rather than crashing")
    func emptyResults() async throws {
        let model = makeSearch([
            DelayedProvider(identifier: .application, category: .application, titles: [])
        ])
        var executed = false
        model.onExecute = { _, _ in executed = true }
        model.query = "zzz"
        try await Task.sleep(for: .milliseconds(200))
        model.execute(secondary: false)
        #expect(executed == false)
    }
}

@Suite("Pinned reorder")
@MainActor
struct PinnedReorderTests {
    private func model(_ pinned: [String]) -> (SidebarViewModel, ConfigurationController) {
        var initial = NexusConfiguration()
        initial.setPinnedApplications(pinned)
        let configuration = ConfigurationController(
            store: InMemoryConfigurationStore(initial),
            events: EventBus(),
            saveDelay: .zero
        )
        return (
            SidebarViewModel(
                applications: FakeApplicationService(),
                configuration: configuration,
                events: EventBus()
            ),
            configuration
        )
    }

    @Test("Move up and move down shift by exactly one slot")
    func moveByOne() {
        let (sidebar, configuration) = model(["a", "b", "c"])
        sidebar.movePinned("c", by: -1)
        #expect(configuration.configuration.pinnedApplications == ["a", "c", "b"])
        sidebar.movePinned("c", by: 1)
        #expect(configuration.configuration.pinnedApplications == ["a", "b", "c"])
    }

    @Test("Moving past either end is refused, not clamped silently into a no-op edit")
    func edges() {
        let (sidebar, configuration) = model(["a", "b"])
        #expect(sidebar.canMovePinned("a", by: -1) == false)
        #expect(sidebar.canMovePinned("b", by: 1) == false)
        #expect(sidebar.canMovePinned("a", by: 1))
        sidebar.movePinned("a", by: -1)
        sidebar.movePinned("b", by: 1)
        #expect(configuration.configuration.pinnedApplications == ["a", "b"])
    }

    @Test("An unpinned identifier cannot be moved")
    func unknown() {
        let (sidebar, configuration) = model(["a"])
        #expect(sidebar.canMovePinned("zzz", by: 1) == false)
        sidebar.movePinned("zzz", by: 1)
        #expect(configuration.configuration.pinnedApplications == ["a"])
    }
}
