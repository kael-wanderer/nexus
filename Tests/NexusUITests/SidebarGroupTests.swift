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

    @Test("The middle of a row groups on drop; either end of it only reorders")
    func zoneDecidesGrouping() async {
        let (model, configuration) = makeModel(["a", "b", "c"], entries: [
            .application("a"), .application("b"), .application("c"),
        ])
        await model.refresh()

        // The end of a row: a reorder, however long the drag rests there.
        model.beginDrag("c")
        model.dragMoved(over: "a", at: .leadingEdge)
        #expect(model.groupCandidate == nil)
        #expect(model.pinned.map(\.id) == ["c", "a", "b"])
        model.endDrag(commit: true)
        #expect(configuration.configuration.pinnedApplications == ["c", "a", "b"])

        // The middle: the candidate appears at once, and nothing slides anywhere.
        model.beginDrag("b")
        model.dragMoved(over: "a", at: .middle)
        #expect(model.groupCandidate == "a")
        #expect(model.pinned.map(\.id) == ["c", "a", "b"])
        model.endDrag(commit: true)

        let entries = configuration.configuration.pinnedEntries
        #expect(entries.count == 2)
        #expect(entries[1].group?.applications == ["a", "b"])
    }

    /// The bug this is here for: the preview used to be reset to the stored order the moment
    /// grouping was decided, so the bar jumped back mid-drag and the reorder was lost.
    @Test("Sliding between a row's middle and its end switches intent, and keeps the preview")
    func zonesSwitchIntent() async {
        let (model, configuration) = makeModel(["a", "b"], entries: [.application("a"), .application("b")])
        await model.refresh()

        model.beginDrag("b")
        model.dragMoved(over: "a", at: .middle)
        #expect(model.groupCandidate == "a")
        model.dragMoved(over: "a", at: .middle)        // the same intent again: nothing changes
        #expect(model.groupCandidate == "a")
        #expect(model.pinned.map(\.id) == ["a", "b"])

        model.dragMoved(over: "a", at: .leadingEdge)   // to the end of the row: a reorder
        #expect(model.groupCandidate == nil)
        #expect(model.pinned.map(\.id) == ["b", "a"])

        model.dragMoved(over: "a", at: .middle)        // back to the middle: the preview stands
        #expect(model.groupCandidate == "a")
        #expect(model.pinned.map(\.id) == ["b", "a"])

        model.endDrag(commit: true)
        #expect(configuration.configuration.pinnedEntries.count == 1)
        #expect(configuration.configuration.pinnedEntries[0].group?.applications == ["a", "b"])
    }

    @Test("The trailing end of a row puts the dragged row after it")
    func trailingEdgeInsertsAfter() async {
        let (model, configuration) = makeModel(["a", "b", "c"], entries: [
            .application("a"), .application("b"), .application("c"),
        ])
        await model.refresh()

        model.beginDrag("a")
        model.dragMoved(over: "b", at: .trailingEdge)
        #expect(model.pinned.map(\.id) == ["b", "a", "c"])
        model.endDrag(commit: true)
        #expect(configuration.configuration.pinnedApplications == ["b", "a", "c"])
    }

    @Test("A cancelled group drag changes nothing")
    func cancelledGroupDrag() async {
        let (model, configuration) = makeModel(["a", "b"], entries: [.application("a"), .application("b")])
        await model.refresh()

        model.beginDrag("b")
        model.dragMoved(over: "a", at: .middle)
        #expect(model.groupCandidate == "a")
        model.endDrag(commit: false)

        #expect(configuration.configuration.pinnedEntries == [.application("a"), .application("b")])
        #expect(model.groupCandidate == nil)
        #expect(model.pinned.map(\.id) == ["a", "b"])
    }

    @Test("A folder never groups, so its middle reorders like the rest of it")
    func foldersDoNotGroup() async {
        let (model, configuration) = makeModel(["a"], entries: [.application("a"), .folder("/tmp")])
        await model.refresh()
        let folder = DockEntry.folder("/tmp").id

        #expect(model.canGroup("a", with: folder) == false)
        model.beginDrag("a")
        model.dragMoved(over: folder, at: .middle)
        #expect(model.groupCandidate == nil)
        model.endDrag(commit: true)
        #expect(configuration.configuration.pinnedEntries == [.folder("/tmp"), .application("a")])
    }

    @Test("Dragging a member out of its group and dropping it in the dock takes it out")
    func dragOutOfGroup() async {
        let (model, configuration) = makeModel(["a", "b", "c", "d"], entries: [
            group("Trio", ["a", "b", "c"]), .application("d"),
        ])
        await model.refresh()

        model.beginDrag("b")
        model.dragMoved(over: "d", at: .leadingEdge)
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

@Suite("The group popover")
@MainActor
struct GroupPopoverTests {
    private func makePopover() -> (GroupPopoverViewModel, SidebarGroup) {
        let group = SidebarGroup(
            group: ApplicationGroup(name: "Pair", applications: ["a", "b"]),
            items: []
        )
        let model = GroupPopoverViewModel()
        model.show(group)
        return (model, group)
    }

    @Test("The list layout draws one width for every group; the grid follows its columns")
    func panelWidth() {
        let (model, _) = makePopover()
        #expect(model.layout == .icons)
        #expect(model.panelWidth == CGFloat(model.columns) * (GroupPopoverView.tileSize + 4)
            + GroupPopoverView.padding * 2)

        model.layout = .list
        #expect(model.panelWidth == GroupPopoverView.listWidth)
    }

    @Test("Clicking the title opens a field with the name in it, and takes the keyboard")
    func beginRename() {
        let (model, _) = makePopover()
        var editing: [Bool] = []
        model.setEditing = { editing.append($0) }

        model.beginRename()
        #expect(model.isRenaming)
        #expect(model.draftName == "Pair")
        #expect(editing == [true])

        model.beginRename()                 // already open: nothing happens twice
        #expect(editing == [true])
    }

    @Test("Return commits the typed name and gives the keyboard back")
    func commitRename() {
        let (model, group) = makePopover()
        var renamed: [String] = []
        var editing: [Bool] = []
        model.rename = { _, name in renamed.append(name) }
        model.setEditing = { editing.append($0) }

        model.beginRename()
        model.draftName = "Work"
        model.commitRename()

        #expect(renamed == ["Work"])
        #expect(model.isRenaming == false)
        #expect(editing == [true, false])
        #expect(model.group?.id == group.id)
    }

    @Test("Escape leaves the name alone; the popover closing keeps what was typed")
    func cancelAndClose() {
        let (model, _) = makePopover()
        var renamed: [String] = []
        model.rename = { _, name in renamed.append(name) }

        model.beginRename()
        model.draftName = "Discarded"
        model.cancelRename()
        #expect(renamed.isEmpty)
        #expect(model.isRenaming == false)

        // Clicking away — which closes the popover — is a commit, not a cancel.
        model.beginRename()
        model.draftName = "Kept"
        model.hide()
        #expect(renamed == ["Kept"])
        #expect(model.isRenaming == false)
        #expect(model.group == nil)
    }
}

@Suite("Naming a group")
struct GroupNamingTests {
    @Test("A shared category names the group")
    func sharedCategory() {
        #expect(
            ApplicationCategory.groupName(
                for: ["public.app-category.developer-tools", "public.app-category.developer-tools"],
                names: ["Xcode", "Terminal"]
            ) == "Developer"
        )
    }

    @Test("Applications that declare no category are named after themselves")
    func noCategory() {
        #expect(
            ApplicationCategory.groupName(for: [nil, nil], names: ["Google Chrome", "Brave Browser"])
                == "Google Chrome & Brave Browser"
        )
        #expect(
            ApplicationCategory.groupName(for: [nil, nil, nil], names: ["Chrome", "Brave", "Safari"])
                == "Chrome & 2 more"
        )
        #expect(ApplicationCategory.groupName(for: [nil], names: ["Chrome"]) == "Chrome")
    }

    @Test("With neither a category nor a name, it is still a Group")
    func nothingToGoOn() {
        #expect(ApplicationCategory.groupName(for: [nil, nil], names: []) == "Group")
        #expect(ApplicationCategory.groupName(for: [nil], names: ["  "]) == "Group")
    }

    @Test("A plurality still wins over the members' names")
    func pluralityWins() {
        #expect(
            ApplicationCategory.groupName(
                for: ["public.app-category.social-networking", nil],
                names: ["Slack", "Chrome"]
            ) == "Social"
        )
    }
}

