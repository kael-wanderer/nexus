import CoreGraphics
import Foundation
import NexusCore
import Testing

@testable import NexusUI

/// One result per provider, so a scope shows up as which categories came back.
private struct OneResultProvider: SearchProvider {
    let identifier: SearchProviderID
    let category: SearchCategory

    func results(for query: SearchQuery, context: SearchContext) async -> [SearchResult] {
        [
            SearchResult(
                id: "\(identifier.rawValue):1",
                title: "\(identifier.rawValue) result",
                icon: .symbol("circle"),
                category: category,
                score: 0.5,
                action: .runBuiltInAction(.openHome)
            )
        ]
    }
}

@MainActor
private func makeSearch() -> SearchViewModel {
    SearchViewModel(
        engine: SearchEngine(providers: [
            OneResultProvider(identifier: .application, category: .application),
            OneResultProvider(identifier: .file, category: .file),
            OneResultProvider(identifier: .action, category: .action),
        ]),
        configuration: ConfigurationController(
            store: InMemoryConfigurationStore(),
            events: EventBus(),
            saveDelay: .zero
        ),
        index: ApplicationIndexSnapshot()
    )
}

@Suite("Search scope in the palette")
@MainActor
struct SearchScopeUITests {
    @Test("A scope re-runs the query without a keystroke and narrows what comes back")
    func scopeNarrowsResults() async {
        let model = makeSearch()
        model.query = "result"
        await until { model.results.count == 3 }

        model.scope = .applications
        await until { model.results.count == 1 }
        #expect(model.results.first?.category == .application)
        #expect(model.query == "result")
    }

    @Test("⌃1…⌃6 pick a scope, and an out-of-range number is ignored")
    func shortcutsSelectScopes() {
        let model = makeSearch()
        model.selectScope(shortcut: 2)
        #expect(model.scope == .applications)
        model.selectScope(shortcut: 9)
        #expect(model.scope == .applications)
        model.selectScope(shortcut: 1)
        #expect(model.scope == .everything)
    }

    @Test("Tab cycles forward, Shift-Tab back")
    func tabCycles() {
        let model = makeSearch()
        model.cycleScope(by: 1)
        #expect(model.scope == .applications)
        model.cycleScope(by: -1)
        #expect(model.scope == .everything)
        model.cycleScope(by: -1)
        #expect(model.scope == .settings)
    }

    @Test("Escape clears a scope before it closes the palette")
    func escapeIsTwoStage() {
        let model = makeSearch()
        var closed = 0
        model.onClose = { closed += 1 }

        model.scope = .folders
        model.cancel()
        #expect(model.scope == .everything)
        #expect(closed == 0)

        model.cancel()
        #expect(closed == 1)
    }

    @Test("Opening the palette starts on Everything, whatever the last search used")
    func scopeResetsOnOpen() {
        let model = makeSearch()
        model.scope = .files
        model.prepareForDisplay()
        #expect(model.scope == .everything)
    }

    @Test("A scope without applications shows nothing for an empty query, not recent applications")
    func emptyQueryUnderAScope() {
        let model = makeSearch()
        model.scope = .folders
        #expect(model.results.isEmpty)
    }
}

@Suite("Palette anchored at the bar")
struct BarAnchorTests {
    private let size = CGSize(width: 640, height: 200)
    private let screen = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)

    private func anchor(_ position: SidebarPosition, bar: CGRect, rowCentre: CGFloat) -> SidebarLayout.BarAnchor {
        SidebarLayout.BarAnchor(bar: bar, screen: screen, rowCentre: rowCentre, position: position)
    }

    @Test("Beside a vertical bar, level with the row")
    func vertical() {
        let bar = CGRect(x: 8, y: 200, width: 64, height: 600)
        let frame = anchor(.left, bar: bar, rowCentre: 100).frame(for: size)
        #expect(frame.minX >= bar.maxX)
        // The anchor is measured down from the bar's top, panels grow up from the bottom.
        #expect(frame.midY == bar.maxY - 100)
    }

    @Test("Above a bottom bar and below a top one")
    func horizontal() {
        let bottom = CGRect(x: 200, y: 8, width: 1_200, height: 64)
        let above = anchor(.bottom, bar: bottom, rowCentre: 600).frame(for: size)
        #expect(above.minY >= bottom.maxY)
        #expect(above.midX == bottom.minX + 600)

        let top = CGRect(x: 200, y: 928, width: 1_200, height: 64)
        let below = anchor(.top, bar: top, rowCentre: 600).frame(for: size)
        #expect(below.maxY <= top.minY)
    }

    @Test("Clamped on screen: a row at the very end does not push the palette off it")
    func clamped() {
        let bar = CGRect(x: 8, y: 0, width: 64, height: 1_000)
        for rowCentre in [CGFloat(0), 999] {
            let frame = anchor(.left, bar: bar, rowCentre: rowCentre).frame(for: size)
            #expect(frame.minY >= screen.minY)
            #expect(frame.maxY <= screen.maxY)
        }

        let wide = CGRect(x: 0, y: 8, width: 1_600, height: 64)
        for rowCentre in [CGFloat(0), 1_599] {
            let frame = anchor(.bottom, bar: wide, rowCentre: rowCentre).frame(for: size)
            #expect(frame.minX >= screen.minX)
            #expect(frame.maxX <= screen.maxX)
        }
    }
}

@Suite("The bar's Search part")
@MainActor
struct SearchBarStyleTests {
    private func makeModel(
        style: SearchBarStyle,
        position: SidebarPosition
    ) -> SidebarViewModel {
        let configuration = ConfigurationController(
            store: InMemoryConfigurationStore(),
            events: EventBus(),
            saveDelay: .zero
        )
        configuration.update {
            $0.search.barStyle = style
            $0.appearance.position = position
        }
        let model = SidebarViewModel(
            applications: FakeApplicationService(),
            configuration: configuration,
            events: EventBus()
        )
        model.openSearch = {}
        return model
    }

    @Test("An icon takes one slot; a box takes three")
    func slots() {
        #expect(makeModel(style: .icon, position: .bottom).searchRowCount == 1)
        #expect(makeModel(style: .field, position: .bottom).searchRowCount == 3)
    }

    @Test("A narrow vertical bar keeps the icon, however the setting is set")
    func verticalStaysNarrow() {
        let model = makeModel(style: .field, position: .left)
        #expect(model.isSearchFieldWide == false)
        #expect(model.searchRowCount == 1)
    }

    @Test("Hover-expanding a vertical bar makes room for the box")
    func expandedVertical() {
        let model = makeModel(style: .field, position: .left)
        model.isExpanded = true
        #expect(model.isSearchFieldWide)
        #expect(model.searchRowCount == 3)
    }

    @Test("The box costs the tail two extra slots, and the sections say so")
    func tailAccounting() {
        let icon = makeModel(style: .icon, position: .bottom)
        let box = makeModel(style: .field, position: .bottom)
        #expect(box.tailRowCount - icon.tailRowCount == 2)
        #expect(box.sectionRowCounts.last == 3)
        #expect(icon.sectionRowCounts.last == 1)
    }
}
