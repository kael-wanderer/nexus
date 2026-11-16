import CoreGraphics
import Foundation
import NexusCore
import Testing

@testable import NexusUI

@MainActor
private func makeModel(pinned: [String], showWindowCount: Bool = true) async -> SidebarViewModel {
    let service = FakeApplicationService(
        pinned.map { makeApplication($0, name: $0.uppercased(), running: true) }
    )
    var initial = NexusConfiguration()
    initial.pinnedEntries = pinned.map { .application($0) }
    initial.general.showStartMenu = false
    initial.behavior.showWindowCount = showWindowCount
    let controller = ConfigurationController(
        store: InMemoryConfigurationStore(initial),
        events: EventBus(),
        saveDelay: .zero
    )
    let model = SidebarViewModel(
        applications: service,
        configuration: controller,
        events: EventBus()
    )
    model.activateWindow = { _ in }
    model.openSearch = {}
    await model.refresh()
    return model
}

@MainActor
@Suite("Row state")
struct RowStateTests {
    @Test("A badge change touches only its own row's state")
    func badgeIsLocal() async {
        let model = await makeModel(pinned: ["com.apple.Safari", "com.apple.Mail"])
        let before = (model.rowState(for: "com.apple.Safari"), model.rowState(for: "com.apple.Mail"))
        model.setBadges(["com.apple.Mail": "3"])
        #expect(model.rowState(for: "com.apple.Safari") == before.0)
        #expect(model.rowState(for: "com.apple.Mail") != before.1)
        #expect(model.rowState(for: "com.apple.Mail").badge == "3")
    }

    @Test("Keyboard focus moving one row changes two states and no others")
    func focusIsLocal() async {
        let model = await makeModel(pinned: ["a.one", "a.two", "a.three"])
        model.beginKeyboardNavigation()
        model.focusFirstRow()
        let before = ["a.one", "a.two", "a.three"].map { model.rowState(for: $0) }
        model.moveFocus(by: 1)
        let after = ["a.one", "a.two", "a.three"].map { model.rowState(for: $0) }
        #expect(zip(before, after).filter { $0 != $1 }.count == 2)
    }

    @Test("A drag marks the dragged row and the row under it, and nothing else")
    func dragIsLocal() async {
        let model = await makeModel(pinned: ["a.one", "a.two", "a.three"])
        let before = model.rowState(for: "a.three")
        model.beginDrag("a.one")
        model.dragMoved(over: "a.two", at: .trailingEdge)
        #expect(model.rowState(for: "a.one").isDragging)
        #expect(model.rowState(for: "a.two").dropEdge != nil)
        #expect(model.rowState(for: "a.three") == before)
    }

    @Test("Window counts show only when the setting is on and the counts are exact")
    func windowCountsNeedBoth() async {
        let off = await makeModel(pinned: ["a.one"], showWindowCount: false)
        off.windowCountsAreExact = true
        #expect(off.rowState(for: "a.one").showsWindowCount == false)

        let on = await makeModel(pinned: ["a.one"], showWindowCount: true)
        on.windowCountsAreExact = true
        #expect(on.rowState(for: "a.one").showsWindowCount == true)
        on.windowCountsAreExact = false
        #expect(on.rowState(for: "a.one").showsWindowCount == false)
    }

    @Test("A row's body reads its item and state, never the model")
    func bodyDoesNotReadModel() throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NexusUI/Sidebar/SidebarView.swift").path
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let start = try #require(source.range(of: "struct SidebarItemView"))
        let tail = source[start.upperBound...]
        let end = try #require(tail.range(of: "private func click"))
        let row = tail[..<end.lowerBound]
        let bodyStart = try #require(row.range(of: "var body: some View {"))
        let afterBody = row[bodyStart.upperBound...]
        let hover = try #require(afterBody.range(of: ".onHover"))
        #expect(!afterBody[..<hover.lowerBound].contains("model."))
    }
}
