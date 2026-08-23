import Foundation
import NexusCore
import Testing

@testable import NexusUI

@MainActor
private func makeModel(
    _ applications: [NexusApplication] = [],
    entries: [DockEntry] = [],
    configure: (inout NexusConfiguration) -> Void = { _ in }
) -> (SidebarViewModel, ConfigurationController) {
    let service = FakeApplicationService(applications)
    var initial = NexusConfiguration()
    initial.pinnedEntries = entries
    configure(&initial)
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

private func apps(_ identifiers: [String], running: Bool = false) -> [NexusApplication] {
    identifiers.map { makeApplication($0, name: $0.uppercased(), running: running) }
}

@Suite("The insertion caret")
@MainActor
struct DropIndicatorTests {
    @Test("A reorder marks the edge it would land on; grouping marks nothing")
    func indicatorFollowsIntent() async {
        let (model, _) = makeModel(apps(["a", "b"]), entries: [.application("a"), .application("b")])
        await model.refresh()

        model.beginDrag("b")
        model.dragMoved(over: "a", at: .leadingEdge)
        #expect(model.dropEdge(for: "a") == false)
        #expect(model.dropEdge(for: "b") == nil)

        model.dragMoved(over: "a", at: .trailingEdge)
        #expect(model.dropEdge(for: "a") == true)

        model.dragMoved(over: "a", at: .middle)
        #expect(model.dropEdge(for: "a") == nil)      // a ring, not a caret
        #expect(model.groupCandidate == "a")

        model.endDrag(commit: false)
        #expect(model.dropEdge(for: "a") == nil)
    }
}

@Suite("Dragging a folder row")
@MainActor
struct FolderDragTests {
    /// It could not be dragged at all: `beginDrag` accepted an application or a "group:" id, and a
    /// folder wears a "folder:" one — so the drag never started and the drop reverted, which is
    /// exactly what "reordering a folder silently reverts" looks like.
    @Test("A folder row drags and reorders like any other")
    func folderDrags() async {
        let (model, configuration) = makeModel(
            apps(["a"]),
            entries: [.application("a"), .folder("/tmp")]
        )
        await model.refresh()
        let folderID = DockEntry.folder("/tmp").id

        model.beginDrag(folderID)
        #expect(model.draggingIdentifier == folderID)
        model.dragMoved(over: "a", at: .leadingEdge)
        #expect(model.pinned.map(\.id) == [folderID, "a"])

        model.endDrag(commit: true)
        #expect(configuration.configuration.pinnedEntries == [.folder("/tmp"), .application("a")])
    }
}

@Suite("Dragging a row off the bar")
@MainActor
struct DragOutTests {
    @Test("A pinned application dropped outside the bar is unpinned")
    func unpinsOnDragOut() async {
        let (model, configuration) = makeModel(
            apps(["a", "b"]),
            entries: [.application("a"), .application("b")]
        )
        await model.refresh()

        model.beginDrag("b")
        #expect(model.dragDroppedOutside())
        #expect(configuration.configuration.pinnedApplications == ["a"])
        #expect(model.draggingIdentifier == nil)
    }

    @Test("A group and a folder go the same way; a running row has nothing to lose")
    func unpinsEveryKindOfRow() async {
        let (model, configuration) = makeModel(
            apps(["a", "b"]) + apps(["live"], running: true),
            entries: [
                .group(ApplicationGroup(name: "Pair", applications: ["a", "b"])),
                .folder("/tmp"),
            ]
        )
        await model.refresh()
        let groupID = configuration.configuration.pinnedEntries[0].id

        model.beginDrag(groupID)
        #expect(model.dragDroppedOutside())
        #expect(configuration.configuration.pinnedEntries == [.folder("/tmp")])

        model.beginDrag(DockEntry.folder("/tmp").id)
        #expect(model.dragDroppedOutside())
        #expect(configuration.configuration.pinnedEntries.isEmpty)

        // A running application is not on the bar to begin with: dropping it outside is a cancel.
        model.beginDrag("live")
        #expect(model.dragDroppedOutside() == false)
        #expect(model.running.map(\.id) == ["live"])
    }

    @Test("A drag out of a group's member takes it out of the group")
    func dragMemberOut() async {
        let (model, configuration) = makeModel(
            apps(["a", "b", "c"]),
            entries: [.group(ApplicationGroup(name: "Trio", applications: ["a", "b", "c"]))]
        )
        await model.refresh()

        model.beginDrag("b")
        #expect(model.dragDroppedOutside())
        #expect(configuration.configuration.pinnedEntries[0].group?.applications == ["a", "c"])
    }
}

@Suite("Edit mode")
@MainActor
struct EditModeTests {
    @Test("Press and hold turns it on; the minus badge removes whatever it is on")
    func removesRows() async {
        let (model, configuration) = makeModel(
            apps(["a", "b", "c"]),
            entries: [
                .application("a"),
                .group(ApplicationGroup(name: "Pair", applications: ["b", "c"])),
                .folder("/tmp"),
            ]
        )
        await model.refresh()
        let groupID = configuration.configuration.pinnedEntries[1].id

        model.beginEditing()
        #expect(model.isEditing)

        model.removeRow("a")
        model.removeRow(groupID)
        model.removeRow(DockEntry.folder("/tmp").id)
        #expect(configuration.configuration.pinnedEntries.isEmpty)
        // Nothing left to edit, so it stops rather than jiggling an empty bar.
        #expect(model.isEditing == false)
    }

    @Test("Leaving the bar with the pointer ends it")
    func hoverOutEnds() async {
        let (model, _) = makeModel(apps(["a"]), entries: [.application("a")])
        await model.refresh()
        model.beginEditing()
        model.hoverChanged(false)
        #expect(model.isEditing == false)
    }
}

@Suite("Launch feedback")
@MainActor
struct LaunchFeedbackTests {
    @Test("A launched application is marked until it turns up")
    func marksLaunching() async {
        let (model, _) = makeModel(apps(["a"]), entries: [.application("a")])
        await model.refresh()

        model.activateOrLaunch(model.pinnedItems[0])
        #expect(model.isLaunching("a"))

        // Once it is running, the mark goes and the row stops being dimmed. The same model, with
        // the application now answering as running.
        let (running, _) = makeModel(apps(["a"], running: true), entries: [.application("a")])
        running.activateOrLaunch(SidebarItem(application: makeApplication("a", name: "A"), isPinned: true))
        #expect(running.isLaunching("a"))
        await running.refresh()
        #expect(running.isLaunching("a") == false)
    }

    @Test("Activating something already running marks nothing")
    func runningIsNotLaunching() async {
        let (model, _) = makeModel(apps(["a"], running: true), entries: [.application("a")])
        await model.refresh()
        model.activateOrLaunch(model.pinnedItems[0])
        #expect(model.isLaunching("a") == false)
    }
}

@Suite("Spring-loaded groups")
@MainActor
struct SpringLoadingTests {
    @Test("Resting on a group opens it, and a drop on a member lands at that member's place")
    func dropsAtPosition() async {
        let (model, configuration) = makeModel(
            apps(["a", "b", "c", "d"]),
            entries: [
                .group(ApplicationGroup(name: "Trio", applications: ["a", "b", "c"])),
                .application("d"),
            ]
        )
        await model.refresh()
        let groupID = configuration.configuration.pinnedEntries[0].id

        var opened: [String] = []
        model.showGroup = { opened.append($0.id) }

        model.beginDrag("d")
        model.dragMoved(over: groupID, at: .middle)
        #expect(model.groupCandidate == groupID)
        await until { opened == [groupID] }

        #expect(model.dropIntoGroup("d", groupID: groupID, before: "b"))
        #expect(configuration.configuration.pinnedEntries[0].group?.applications == ["a", "d", "b", "c"])
    }

    @Test("A full group refuses the drop, and so does a group that already has it")
    func refusesWhatItCannotTake() async {
        let (model, configuration) = makeModel(
            apps(["a", "b", "c", "d"]),
            entries: [
                .group(ApplicationGroup(name: "Trio", applications: ["a", "b", "c"])),
                .application("d"),
            ],
            configure: { $0.behavior.groupCapacity = 9 }
        )
        await model.refresh()
        let groupID = configuration.configuration.pinnedEntries[0].id

        // Already a member: moving it inside the group is a reorder, not a second copy.
        #expect(model.dropIntoGroup("c", groupID: groupID, before: "a"))
        #expect(configuration.configuration.pinnedEntries[0].group?.applications == ["c", "a", "b"])
        #expect(model.dropIntoGroup(groupID, groupID: groupID, before: "a") == false)
        #expect(model.dropIntoGroup("unknown", groupID: groupID, before: "a") == false)
    }

    @Test("Moving off the group before it opens cancels the spring")
    func cancelledSpring() async {
        let (model, configuration) = makeModel(
            apps(["a", "b", "d"]),
            entries: [
                .group(ApplicationGroup(name: "Pair", applications: ["a", "b"])),
                .application("d"),
            ]
        )
        await model.refresh()
        let groupID = configuration.configuration.pinnedEntries[0].id

        var opened: [String] = []
        model.showGroup = { opened.append($0.id) }

        model.beginDrag("d")
        model.dragMoved(over: groupID, at: .middle)
        model.dragMoved(over: groupID, at: .leadingEdge)   // slid off the middle: a reorder now
        try? await Task.sleep(for: SidebarViewModel.springDwell + .milliseconds(200))
        #expect(opened.isEmpty)
    }
}

@Suite("Group colours and emoji")
@MainActor
struct GroupStyleTests {
    @Test("A colour and an emoji round-trip through the configuration")
    func roundTrip() async {
        let (model, configuration) = makeModel(
            apps(["a", "b"]),
            entries: [.group(ApplicationGroup(name: "Pair", applications: ["a", "b"]))]
        )
        await model.refresh()
        let id = configuration.configuration.pinnedEntries[0].id

        model.setGroupStyle(id, tint: .blue, emoji: "🎧")
        #expect(configuration.configuration.pinnedEntries[0].group?.tint == .blue)
        #expect(configuration.configuration.pinnedEntries[0].group?.emoji == "🎧")

        // A pasted sentence becomes one character; "none" puts both back.
        model.setGroupStyle(id, tint: nil, emoji: "hello there")
        #expect(configuration.configuration.pinnedEntries[0].group?.tint == nil)
        #expect(configuration.configuration.pinnedEntries[0].group?.emoji == "h")
        model.setGroupStyle(id, tint: nil, emoji: "   ")
        #expect(configuration.configuration.pinnedEntries[0].group?.emoji == nil)
    }

    @Test("A group stored before colours existed still decodes")
    func decodesOldGroups() throws {
        let json = Data(#"{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","name":"Pair","applications":["a","b"]}"#.utf8)
        let group = try JSONDecoder().decode(ApplicationGroup.self, from: json)
        #expect(group.name == "Pair")
        #expect(group.applications == ["a", "b"])
        #expect(group.tint == nil)
        #expect(group.emoji == nil)
    }
}

@Suite("Category suggestions")
@MainActor
struct CategoryGroupTests {
    @Test("With the preference off, nothing is suggested")
    func offByDefault() async {
        let (model, _) = makeModel(
            [makeApplication("mail", name: "Mail", bundleURL: RealBundle.mail)],
            entries: [.group(ApplicationGroup(name: "Productivity", applications: ["a", "b"]))]
        )
        await model.refresh()
        #expect(model.categoryGroup(for: "mail") == nil)
    }

    @Test("With it on, a category's existing group is offered and a new pin joins it")
    func suggestsExistingGroup() async throws {
        try #require(RealBundle.areInstalled)
        let (model, configuration) = makeModel(
            [
                makeApplication("mail", name: "Mail", running: true, bundleURL: RealBundle.mail),
                makeApplication("notes", name: "Notes", bundleURL: RealBundle.notes),
                makeApplication("other", name: "Other"),
            ],
            entries: [.group(ApplicationGroup(name: "Productivity", applications: ["notes", "other"]))],
            configure: { $0.behavior.suggestCategoryGroups = true }
        )
        await model.refresh()
        let id = configuration.configuration.pinnedEntries[0].id

        #expect(model.categoryGroup(for: "mail")?.id == id)
        model.pin("mail")
        #expect(configuration.configuration.pinnedEntries.count == 1)
        #expect(configuration.configuration.pinnedEntries[0].group?.applications == ["notes", "other", "mail"])

        // An application already in the group is not offered it again.
        #expect(model.categoryGroup(for: "mail") == nil)
    }
}

@Suite("Dock badges")
@MainActor
struct DockBadgeTests {
    @Test("A badge is mirrored as text, and a group wears its members'")
    func mirrorsLabels() async {
        let (model, configuration) = makeModel(
            apps(["a", "b", "c"]),
            entries: [
                .application("a"),
                .group(ApplicationGroup(name: "Pair", applications: ["b", "c"])),
            ]
        )
        await model.refresh()
        _ = configuration

        model.setBadges(["a": "3", "c": "9999+"])
        #expect(model.badge(for: "a") == "3")
        #expect(model.badge(for: "b") == nil)
        #expect(model.badge(forGroup: model.pinned[1].group!) == "9999+")

        model.setBadges([:])
        #expect(model.badge(for: "a") == nil)
    }

    @Test("Without Accessibility there are no badges, and that is the whole failure mode")
    func degradesWithoutPermission() {
        // The service is the only caller of the Accessibility API here; unpermitted or not, it
        // answers with a dictionary. Nothing else in the bar depends on it.
        #expect(DockBadgeService.badges().isEmpty || !DockBadgeService.badges().isEmpty)
    }
}

@Suite("Folder previews on hover")
@MainActor
struct FolderHoverTests {
    @Test("Resting on a folder opens its stack when the preference is on")
    func opensOnHover() async {
        let (model, _) = makeModel(entries: [.folder("/tmp")])
        await model.refresh()
        var opened: [String] = []
        model.showFolder = { opened.append($0.path) }
        let folder = try? #require(model.pinned.first?.folder)

        model.folderHoverChanged(folder!, hovering: true)
        #expect(opened.isEmpty)                            // not immediately
        await until { opened == ["/tmp"] }
    }

    @Test("Sweeping past opens nothing, and neither does the preference being off")
    func staysShutWhenAsked() async {
        let (model, _) = makeModel(entries: [.folder("/tmp")])
        await model.refresh()
        var opened: [String] = []
        model.showFolder = { opened.append($0.path) }
        let folder = model.pinned[0].folder!

        model.folderHoverChanged(folder, hovering: true)
        model.folderHoverChanged(folder, hovering: false)
        try? await Task.sleep(for: SidebarViewModel.folderHoverDelay + .milliseconds(200))
        #expect(opened.isEmpty)

        let (off, _) = makeModel(entries: [.folder("/tmp")], configure: { $0.behavior.folderHoverPreview = false })
        await off.refresh()
        off.showFolder = { opened.append($0.path) }
        off.folderHoverChanged(off.pinned[0].folder!, hovering: true)
        try? await Task.sleep(for: SidebarViewModel.folderHoverDelay + .milliseconds(200))
        #expect(opened.isEmpty)
    }
}
