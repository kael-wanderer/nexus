import Foundation
import NexusCore
import Testing

@testable import NexusUI

@MainActor
private func makeModel(
    _ applications: [NexusApplication] = [],
    pinned: [String] = []
) -> (SidebarViewModel, FakeApplicationService, ConfigurationController) {
    let service = FakeApplicationService(applications)
    var initial = NexusConfiguration()
    initial.pinnedApplications = pinned
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
    return (model, service, controller)
}

@Suite("SidebarViewModel")
@MainActor
struct SidebarViewModelTests {
    @Test("Pinned applications keep their stored order, running-only apps go in their own section")
    func sections() async {
        let (model, _, _) = makeModel(
            [
                makeApplication("com.apple.Safari", name: "Safari", running: true),
                makeApplication("com.apple.Terminal", name: "Terminal"),
                makeApplication("com.apple.Music", name: "Music", running: true),
            ],
            pinned: ["com.apple.Terminal", "com.apple.Safari"]
        )
        await model.refresh()

        #expect(model.pinned.map(\.id) == ["com.apple.Terminal", "com.apple.Safari"])
        #expect(model.running.map(\.id) == ["com.apple.Music"])
        #expect(model.pinned[1].isRunning)
        #expect(model.pinned[0].isRunning == false)
    }

    @Test("A pinned application whose bundle has vanished is dropped, not rendered broken")
    func missingBundle() async {
        let (model, _, _) = makeModel([], pinned: ["com.example.gone"])
        await model.refresh()
        #expect(model.pinned.isEmpty)
    }

    @Test("Clicking a running application activates it; a stopped one launches")
    func clickBehaviour() async throws {
        let (model, service, _) = makeModel(
            [
                makeApplication("com.apple.Safari", name: "Safari", running: true),
                makeApplication("com.apple.Terminal", name: "Terminal"),
            ],
            pinned: ["com.apple.Safari", "com.apple.Terminal"]
        )
        await model.refresh()

        model.activateOrLaunch(model.pinned[0])
        model.activateOrLaunch(model.pinned[1])
        try await Task.sleep(for: .milliseconds(50))

        #expect(await service.activated == ["com.apple.Safari"])
        #expect(await service.launched == ["com.apple.Terminal"])
    }

    @Test("Pin, unpin and reorder all round-trip through the configuration")
    func pinning() async {
        let (model, _, configuration) = makeModel(
            [
                makeApplication("a", name: "A"),
                makeApplication("b", name: "B"),
                makeApplication("c", name: "C"),
            ],
            pinned: ["a", "b"]
        )
        model.pin("c")
        #expect(configuration.configuration.pinnedApplications == ["a", "b", "c"])

        model.pin("c")   // idempotent
        #expect(configuration.configuration.pinnedApplications == ["a", "b", "c"])

        model.movePinned("c", before: "a")
        #expect(configuration.configuration.pinnedApplications == ["c", "a", "b"])

        model.movePinnedToEnd("c")
        #expect(configuration.configuration.pinnedApplications == ["a", "b", "c"])

        model.unpin("b")
        #expect(configuration.configuration.pinnedApplications == ["a", "c"])
    }

    @Test("A reorder payload that is not a pinned identifier is ignored")
    func rejectsForeignDragPayload() async {
        let (model, _, configuration) = makeModel([], pinned: ["a", "b"])
        model.movePinned("/Users/someone/Downloads/thing.txt", before: "a")
        model.movePinned("a", before: "not-pinned")
        model.movePinned("a", before: "a")
        #expect(configuration.configuration.pinnedApplications == ["a", "b"])
    }

    @Test("Dragging a pinned row previews the move, and the drop commits it")
    func dragPreviewCommits() async {
        let (model, _, configuration) = makeModel(
            [makeApplication("a", name: "A"), makeApplication("b", name: "B"), makeApplication("c", name: "C")],
            pinned: ["a", "b", "c"]
        )
        await model.refresh()

        model.beginDrag("c")
        model.dragMoved(over: "a")
        // The rows have already moved; the stored order has not.
        #expect(model.pinned.map(\.id) == ["c", "a", "b"])
        #expect(configuration.configuration.pinnedApplications == ["a", "b", "c"])

        model.endDrag(commit: true)
        #expect(configuration.configuration.pinnedApplications == ["c", "a", "b"])
        #expect(model.draggingIdentifier == nil)
    }

    @Test("Dragging a running application into the pinned section previews and then pins it")
    func dragRunningIntoPinned() async {
        let (model, _, configuration) = makeModel(
            [
                makeApplication("a", name: "A"),
                makeApplication("b", name: "B"),
                makeApplication("new", name: "New", running: true),
            ],
            pinned: ["a", "b"]
        )
        await model.refresh()
        #expect(model.running.map(\.id) == ["new"])

        model.beginDrag("new")
        model.dragMoved(over: "b")
        // Previewed in the pinned section, gone from the running one, nothing stored yet.
        #expect(model.pinned.map(\.id) == ["a", "new", "b"])
        #expect(model.running.isEmpty)
        #expect(configuration.configuration.pinnedApplications == ["a", "b"])

        model.endDrag(commit: true)
        #expect(configuration.configuration.pinnedApplications == ["a", "new", "b"])
    }

    @Test("A running application dragged and then dropped outside stays unpinned")
    func dragRunningCancelled() async {
        let (model, _, configuration) = makeModel(
            [makeApplication("a", name: "A"), makeApplication("new", name: "New", running: true)],
            pinned: ["a"]
        )
        await model.refresh()

        model.beginDrag("new")
        model.dragMoved(over: "a")
        model.endDrag(commit: false)

        #expect(configuration.configuration.pinnedApplications == ["a"])
        #expect(model.running.map(\.id) == ["new"])
    }

    @Test("Two running applications can be reordered against each other")
    func dragWithinRunning() async {
        let (model, _, configuration) = makeModel(
            [
                makeApplication("chatgpt", name: "ChatGPT", running: true),
                makeApplication("claude", name: "Claude", running: true),
            ]
        )
        await model.refresh()
        #expect(model.running.map(\.id) == ["chatgpt", "claude"])

        model.beginDrag("claude")
        model.dragMoved(over: "chatgpt")
        #expect(model.running.map(\.id) == ["claude", "chatgpt"])

        model.endDrag(commit: true)
        #expect(configuration.configuration.runningApplicationOrder == ["claude", "chatgpt"])
        #expect(configuration.configuration.pinnedApplications.isEmpty)
        #expect(model.running.map(\.id) == ["claude", "chatgpt"])
    }

    @Test("An application nobody has moved keeps its alphabetical place")
    func alphabeticalFallback() async {
        let (model, _, _) = makeModel(
            [
                makeApplication("b", name: "Bravo", running: true),
                makeApplication("a", name: "Alpha", running: true),
                makeApplication("c", name: "Charlie", running: true),
            ]
        )
        await model.refresh()
        model.beginDrag("c")
        model.dragMoved(over: "a")
        model.endDrag(commit: true)
        // Charlie was moved to the front; Alpha and Bravo keep their alphabetical order behind it.
        #expect(model.running.map(\.id) == ["c", "a", "b"])
    }

    @Test("Dragging a pinned row into the running section unpins it")
    func dragPinnedOut() async {
        let (model, _, configuration) = makeModel(
            [
                makeApplication("a", name: "A", running: true),
                makeApplication("live", name: "Live", running: true),
            ],
            pinned: ["a"]
        )
        await model.refresh()

        model.beginDrag("a")
        model.dragMoved(over: "live")
        #expect(model.pinned.isEmpty)

        model.endDrag(commit: true)
        #expect(configuration.configuration.pinnedApplications.isEmpty)
        #expect(model.running.map(\.id) == ["a", "live"])
    }

    @Test("A cancelled drag leaves the stored order untouched")
    func dragCancelled() async {
        let (model, _, configuration) = makeModel(
            [makeApplication("a", name: "A"), makeApplication("b", name: "B")],
            pinned: ["a", "b"]
        )
        await model.refresh()

        model.beginDrag("b")
        model.dragMoved(over: "a")
        #expect(model.pinned.map(\.id) == ["b", "a"])

        model.endDrag(commit: false)
        #expect(configuration.configuration.pinnedApplications == ["a", "b"])
        #expect(model.draggingIdentifier == nil)
    }

    @Test("A drag payload for an application the sidebar does not know is ignored")
    func unknownDragPayload() async {
        let (model, _, _) = makeModel([makeApplication("a", name: "A")], pinned: ["a"])
        await model.refresh()
        model.beginDrag("/Users/someone/Downloads/thing.txt")
        #expect(model.draggingIdentifier == nil)
    }

    @Test("Dropping a running application on a pinned one pins it in that slot")
    func dropPins() async {
        let (model, _, configuration) = makeModel(
            [makeApplication("new", name: "New", running: true)],
            pinned: ["a", "b"]
        )
        model.dropPinned("new", on: "b")
        #expect(configuration.configuration.pinnedApplications == ["a", "new", "b"])
    }

    @Test("A drop that lands on a row that is not pinned changes nothing")
    func dropOnUnpinnedTarget() async {
        let (model, _, configuration) = makeModel([], pinned: ["a", "b"])
        model.dropPinned("new", on: "not-pinned")
        model.dropPinned("a", on: "a")
        #expect(configuration.configuration.pinnedApplications == ["a", "b"])
    }

    @Test("Window titles come from the cache, and only when raising a window is possible")
    func windowMenuCache() async {
        let (model, _, _) = makeModel([makeApplication("a", name: "A", running: true)], pinned: ["a"])
        let identity = ApplicationIdentity(bundleIdentifier: "a")
        let window = NexusWindow(
            identity: WindowIdentity(owner: identity, number: 1),
            title: "Design",
            applicationName: "A"
        )
        model.setWindows([window], for: identity)

        // Without an injected activateWindow there is nothing the menu could do with the list.
        #expect(model.windows(for: identity).isEmpty)

        model.activateWindow = { _ in }
        #expect(model.windows(for: identity).map(\.title) == ["Design"])
        #expect(model.windows(for: ApplicationIdentity(bundleIdentifier: "b")).isEmpty)
    }

    @Test("Hover expand is suppressed when the behaviour is disabled")
    func hoverExpandDisabled() async {
        let (model, _, configuration) = makeModel()
        model.hoverChanged(true)
        #expect(model.isExpanded)

        configuration.update { $0.behavior.hoverExpand = false }
        model.configurationChanged()
        model.hoverChanged(true)
        #expect(model.isExpanded == false)
    }

    @Test("Section row counts drive the panel height and exclude hidden sections")
    func sectionRowCounts() async {
        let (model, _, configuration) = makeModel(
            [makeApplication("a", name: "A", running: true), makeApplication("b", name: "B", running: true)],
            pinned: ["a"]
        )
        await model.refresh()
        // The last section is the always-present utility row (Trash; Search is not injected here).
        #expect(model.sectionRowCounts == [1, 1, 1])

        configuration.update { $0.behavior.showRunningApplications = false }
        #expect(model.sectionRowCounts == [1, 1])
    }

    @Test("Only .app bundles are accepted from a Finder drop")
    func finderDrop() async {
        let (model, _, configuration) = makeModel()
        let accepted = model.pinApplications(at: [URL(fileURLWithPath: "/tmp/notes.txt")])
        #expect(accepted == false)
        #expect(configuration.configuration.pinnedApplications.isEmpty)
    }
}
