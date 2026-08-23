import Foundation
import NexusCore
import Testing

@testable import NexusUI

@MainActor
private func makeModel(
    _ identifiers: [String],
    entries: [DockEntry],
    capacity: Int = 9
) -> (SidebarViewModel, ConfigurationController) {
    let service = FakeApplicationService(identifiers.map { makeApplication($0, name: $0.uppercased()) })
    var initial = NexusConfiguration()
    initial.pinnedEntries = entries
    initial.behavior.groupCapacity = capacity
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
    return (model, controller)
}

private func group(_ name: String, _ applications: [String]) -> DockEntry {
    .group(ApplicationGroup(name: name, applications: applications))
}

@MainActor
@Suite("Application groups")
struct SidebarGroupTests {
    @Test("Dropping one application onto another puts both in a group, in that order")
    func createsGroup() async {
        let (model, configuration) = makeModel(["a", "b", "c"], entries: [
            .application("a"), .application("b"), .application("c"),
        ])
        await model.refresh()

        #expect(model.group("c", with: "a"))

        let entries = configuration.configuration.pinnedEntries
        #expect(entries.count == 2)
        #expect(entries[0].group?.applications == ["a", "c"])
        #expect(entries[1] == .application("b"))
        // The rows follow: one group row, one application row.
        #expect(model.pinned.map(\.id) == [entries[0].id, "b"])
        #expect(model.pinned[0].group?.items.map(\.id) == ["a", "c"])
    }

    @Test("Dropping an application onto a group adds it, and a full group refuses")
    func joinsAndRefuses() async {
        let members = ["m1", "m2", "m3"]
        let (model, configuration) = makeModel(members + ["a", "b"], entries: [
            group("Trio", members), .application("a"), .application("b"),
        ])
        await model.refresh()
        let id = configuration.configuration.pinnedEntries[0].id

        #expect(model.canGroup("a", with: id))
        #expect(model.group("a", with: id))
        #expect(configuration.configuration.pinnedEntries[0].group?.applications == members + ["a"])

        // Same group, capacity 4 this time: no room, so the drop is never offered.
        let (small, smallConfiguration) = makeModel(["m1", "m2", "m3", "m4", "x"], entries: [
            group("Full", ["m1", "m2", "m3", "m4"]), .application("x"),
        ], capacity: 4)
        await small.refresh()
        let fullID = smallConfiguration.configuration.pinnedEntries[0].id

        #expect(small.canGroup("x", with: fullID) == false)
        #expect(small.group("x", with: fullID) == false)
        #expect(smallConfiguration.configuration.pinnedEntries[1] == .application("x"))
    }

    @Test("A group cannot be dragged into another group; only applications group")
    func groupsDoNotNest() async {
        let (model, configuration) = makeModel(["a", "b", "c", "d"], entries: [
            group("One", ["a", "b"]), group("Two", ["c", "d"]),
        ])
        await model.refresh()
        let first = configuration.configuration.pinnedEntries[0].id
        let second = configuration.configuration.pinnedEntries[1].id

        #expect(model.canGroup(first, with: second) == false)
        #expect(model.group(first, with: second) == false)
        #expect(configuration.configuration.pinnedEntries.count == 2)
    }

    @Test("Taking an application out of a group leaves it pinned beside it")
    func removeFromGroup() async {
        let (model, configuration) = makeModel(["a", "b", "c"], entries: [group("Trio", ["a", "b", "c"])])
        await model.refresh()

        model.removeFromGroup("b")

        let entries = configuration.configuration.pinnedEntries
        #expect(entries[0].group?.applications == ["a", "c"])
        #expect(entries[1] == .application("b"))
    }

    /// A folder of one is a lie: taking the second-to-last application out has to dissolve it.
    @Test("Removing the second-to-last member dissolves the group")
    func dissolvesAtOne() async {
        let (model, configuration) = makeModel(["a", "b"], entries: [group("Pair", ["a", "b"])])
        await model.refresh()

        model.removeFromGroup("a")

        #expect(configuration.configuration.pinnedEntries == [.application("b"), .application("a")])
        #expect(model.pinned.allSatisfy { $0.group == nil })
    }

    @Test("Unpinning a member from inside a group leaves the rest of the dock alone")
    func unpinMember() async {
        let (model, configuration) = makeModel(["a", "b", "c", "d"], entries: [
            group("Trio", ["a", "b", "c"]), .application("d"),
        ])
        await model.refresh()

        model.unpin("b")

        #expect(configuration.configuration.pinnedEntries[0].group?.applications == ["a", "c"])
        #expect(configuration.configuration.pinnedEntries[1] == .application("d"))
    }

    @Test("Ungrouping leaves the applications pinned in the group's place and order")
    func ungroup() async {
        let (model, configuration) = makeModel(["a", "b", "c", "d"], entries: [
            .application("d"), group("Trio", ["a", "b", "c"]),
        ])
        await model.refresh()
        let id = configuration.configuration.pinnedEntries[1].id

        model.ungroup(id)

        #expect(
            configuration.configuration.pinnedEntries
                == [.application("d"), .application("a"), .application("b"), .application("c")]
        )
    }

    @Test("Removing a group takes its applications with it")
    func unpinGroup() async {
        let (model, configuration) = makeModel(["a", "b", "c"], entries: [
            group("Pair", ["a", "b"]), .application("c"),
        ])
        await model.refresh()
        let id = configuration.configuration.pinnedEntries[0].id

        model.unpinGroup(id)

        #expect(configuration.configuration.pinnedEntries == [.application("c")])
    }

    @Test("A group can be renamed, and an empty name falls back rather than being stored")
    func rename() async {
        let (model, configuration) = makeModel(["a", "b"], entries: [group("Pair", ["a", "b"])])
        await model.refresh()
        let id = configuration.configuration.pinnedEntries[0].id

        model.renameGroup(id, to: "  Work  ")
        #expect(configuration.configuration.pinnedEntries[0].group?.name == "Work")

        model.renameGroup(id, to: "   ")
        #expect(configuration.configuration.pinnedEntries[0].group?.name == ApplicationCategory.fallbackName)
    }

    @Test("Groups reorder as one row, and move like any other")
    func reorder() async {
        let (model, configuration) = makeModel(["a", "b", "c"], entries: [
            .application("c"), group("Pair", ["a", "b"]),
        ])
        await model.refresh()
        let id = configuration.configuration.pinnedEntries[1].id

        #expect(model.canMovePinned(id, by: -1))
        model.movePinned(id, by: -1)
        #expect(configuration.configuration.pinnedEntries[0].id == id)
        #expect(model.canMovePinned(id, by: -1) == false)

        model.movePinnedToEnd(id)
        #expect(configuration.configuration.pinnedEntries[1].id == id)
    }

    @Test("Resting a drag on a row groups on drop; dragging past it only reorders")
    func dwellDecidesGrouping() async {
        let (model, configuration) = makeModel(["a", "b", "c"], entries: [
            .application("a"), .application("b"), .application("c"),
        ])
        await model.refresh()

        // Passing over a row: no dwell elapses, so the drop is a reorder.
        model.beginDrag("c")
        model.dragMoved(over: "a")
        #expect(model.groupCandidate == nil)
        model.endDrag(commit: true)
        #expect(configuration.configuration.pinnedApplications == ["c", "a", "b"])

        // Resting on it: the candidate appears, the rows stop sliding, and the drop groups.
        model.beginDrag("b")
        model.dragMoved(over: "a")
        await until { model.groupCandidate == "a" }
        #expect(model.pinned.map(\.id) == ["c", "a"])   // the dragged row has left the bar
        model.endDrag(commit: true)

        let entries = configuration.configuration.pinnedEntries
        #expect(entries.count == 2)
        #expect(entries[1].group?.applications == ["a", "b"])
    }

    @Test("A cancelled group drag changes nothing")
    func cancelledDwell() async {
        let (model, configuration) = makeModel(["a", "b"], entries: [.application("a"), .application("b")])
        await model.refresh()

        model.beginDrag("b")
        model.dragMoved(over: "a")
        await until { model.groupCandidate == "a" }
        model.endDrag(commit: false)

        #expect(configuration.configuration.pinnedEntries == [.application("a"), .application("b")])
        #expect(model.groupCandidate == nil)
        #expect(model.pinned.map(\.id) == ["a", "b"])
    }

    @Test("Dragging a member out of its group and dropping it in the dock takes it out")
    func dragOutOfGroup() async {
        let (model, configuration) = makeModel(["a", "b", "c", "d"], entries: [
            group("Trio", ["a", "b", "c"]), .application("d"),
        ])
        await model.refresh()

        model.beginDrag("b")
        model.dragMoved(over: "d")
        // Three rows while the drag is in flight: the group it left, the row it is being dragged
        // as, and "d".
        #expect(model.pinned.map(\.id).contains("b"))
        #expect(model.pinned.count == 3)
        model.endDrag(commit: true)

        let entries = configuration.configuration.pinnedEntries
        #expect(entries[0].group?.applications == ["a", "c"])
        #expect(entries[1] == .application("b"))
        #expect(entries[2] == .application("d"))
    }

    @Test("A group whose applications have all been uninstalled leaves the dock intact")
    func vanishedMembers() async {
        // Only "d" is installed; the group's members are not.
        let (model, _) = makeModel(["d"], entries: [group("Gone", ["a", "b"]), .application("d")])
        await model.refresh()

        #expect(model.pinned.map(\.id) == ["d"])
    }

    @Test("A group's row is running when any member is, and lists no window count")
    func runningState() async {
        let service = FakeApplicationService([
            makeApplication("a", name: "A"),
            makeApplication("b", name: "B", running: true),
        ])
        var initial = NexusConfiguration()
        initial.pinnedEntries = [group("Pair", ["a", "b"])]
        let configuration = ConfigurationController(
            store: InMemoryConfigurationStore(initial),
            events: EventBus(),
            saveDelay: .zero
        )
        let model = SidebarViewModel(applications: service, configuration: configuration, events: EventBus())
        await model.refresh()

        #expect(model.pinned[0].group?.isRunning == true)
        #expect(model.pinnedItems.map(\.id) == ["a", "b"])
    }

    @Test("The pinned section still counts one row per group, not one per application")
    func rowCounts() async {
        let (model, _) = makeModel(["a", "b", "c"], entries: [group("Pair", ["a", "b"]), .application("c")])
        await model.refresh()

        #expect(model.pinned.count == 2)
        #expect(model.sectionRowCounts.first == 2)
    }
}
