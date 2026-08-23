import CoreGraphics
import Foundation
import NexusCore
import Testing

@testable import NexusUI

@MainActor
private func makeStartMenu(
    _ applications: [NexusApplication],
    frecency: [String: FrecencyEntry] = [:]
) -> (StartMenuViewModel, ConfigurationController) {
    var initial = NexusConfiguration()
    initial.frecency = frecency
    let configuration = ConfigurationController(
        store: InMemoryConfigurationStore(initial),
        events: EventBus(),
        saveDelay: .zero
    )
    let index = ApplicationIndexSnapshot()
    index.write(applications)
    let model = StartMenuViewModel(
        index: index,
        configuration: configuration,
        launcher: FakeApplicationService(applications)
    )
    return (model, configuration)
}

@MainActor
@Suite("Start menu")
struct StartMenuTests {
    @Test("With no query the grid leads with recent applications, then everything else A–Z")
    func recentsFirst() {
        let (model, _) = makeStartMenu(
            [
                makeApplication("a", name: "Alpha"),
                makeApplication("b", name: "Bravo"),
                makeApplication("c", name: "Charlie"),
            ],
            frecency: ["app:c": FrecencyEntry(count: 5, lastUsed: Date())]
        )
        model.prepareForDisplay()

        #expect(model.applications.map(\.name) == ["Charlie", "Alpha", "Bravo"])
        #expect(model.recentCutoff == 1)
    }

    @Test("Typing filters the grid and drops what does not match")
    func filters() {
        let (model, _) = makeStartMenu([
            makeApplication("a", name: "Alpha"),
            makeApplication("b", name: "Bravo"),
            makeApplication("c", name: "Alphabet"),
        ])
        model.prepareForDisplay()

        model.query = "alph"
        #expect(model.applications.map(\.name) == ["Alpha", "Alphabet"])

        model.query = "zzz"
        #expect(model.applications.isEmpty)
        #expect(model.selectedApplication == nil)
    }

    @Test("Arrow keys walk the grid: one by one sideways, a row at a time vertically")
    func selectionMoves() {
        let names = ["A", "B", "C", "D", "E", "F"]
        let (model, _) = makeStartMenu(names.map { makeApplication($0, name: $0) })
        model.prepareForDisplay()

        model.moveSelection(by: 1, columns: 4)
        #expect(model.selectedIndex == 1)

        model.moveSelection(by: 4, columns: 4)          // down one row
        #expect(model.selectedIndex == 5)

        model.moveSelection(by: 4, columns: 4)          // clamped at the end
        #expect(model.selectedIndex == 5)

        model.moveSelection(by: -4, columns: 4)
        #expect(model.selectedIndex == 1)

        model.moveSelection(by: -1, columns: 4)
        model.moveSelection(by: -1, columns: 4)          // clamped at the start
        #expect(model.selectedIndex == 0)
    }

    @Test("Launching records frecency and closes the menu")
    func launchRecordsAndCloses() {
        let (model, configuration) = makeStartMenu([makeApplication("a", name: "Alpha")])
        model.prepareForDisplay()

        var closed = 0
        model.onClose = { closed += 1 }
        model.launchSelected()

        #expect(configuration.configuration.frecency["app:a"]?.count == 1)
        #expect(closed == 1)
    }
}

@Suite("Start menu placement")
struct StartMenuLayoutTests {
    private let visible = CGRect(x: 0, y: 0, width: 1_440, height: 875)
    private let size = CGSize(width: 560, height: 400)

    @Test("Each corner puts the panel in that corner, inside the visible frame")
    func corners() {
        let margin = StartMenuLayout.margin

        let bottomLeading = StartMenuLayout.frame(size: size, in: visible, corner: .bottomLeading)
        #expect(bottomLeading.minX == visible.minX + margin)
        #expect(bottomLeading.minY == visible.minY + margin)

        let bottomTrailing = StartMenuLayout.frame(size: size, in: visible, corner: .bottomTrailing)
        #expect(bottomTrailing.maxX == visible.maxX - margin)
        #expect(bottomTrailing.minY == visible.minY + margin)

        let topLeading = StartMenuLayout.frame(size: size, in: visible, corner: .topLeading)
        #expect(topLeading.minX == visible.minX + margin)
        #expect(topLeading.maxY == visible.maxY - margin)

        let topTrailing = StartMenuLayout.frame(size: size, in: visible, corner: .topTrailing)
        #expect(topTrailing.maxX == visible.maxX - margin)
        #expect(topTrailing.maxY == visible.maxY - margin)

        for frame in [bottomLeading, bottomTrailing, topLeading, topTrailing] {
            #expect(visible.contains(frame))
        }
    }

    @Test("A panel larger than the display is clamped rather than pushed off it")
    func clamped() {
        let huge = CGSize(width: 5_000, height: 5_000)
        let frame = StartMenuLayout.frame(size: huge, in: visible, corner: .topTrailing)
        #expect(frame.width == visible.width - StartMenuLayout.margin * 2)
        #expect(frame.height == visible.height - StartMenuLayout.margin * 2)
        #expect(visible.contains(frame))
    }

    @Test("Placement works on a display with a negative origin")
    func secondaryDisplay() {
        let secondary = CGRect(x: -1_920, y: 200, width: 1_920, height: 1_080)
        let frame = StartMenuLayout.frame(size: size, in: secondary, corner: .bottomLeading)
        #expect(frame.minX == secondary.minX + StartMenuLayout.margin)
        #expect(secondary.contains(frame))
    }

    @Test("The default corner is the one nearest the bar")
    func defaultCorner() {
        #expect(StartMenuLayout.defaultCorner(for: .left) == .bottomLeading)
        #expect(StartMenuLayout.defaultCorner(for: .right) == .bottomTrailing)
        #expect(StartMenuLayout.defaultCorner(for: .bottom) == .bottomLeading)
        #expect(StartMenuLayout.defaultCorner(for: .top) == .topLeading)
    }
}
