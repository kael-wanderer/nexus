import Foundation
import NexusCore
import Testing

@testable import NexusUI

@MainActor
private func makeModel(
    _ identifiers: [String] = [],
    entries: [DockEntry] = []
) -> (SidebarViewModel, ConfigurationController) {
    let service = FakeApplicationService(identifiers.map { makeApplication($0, name: $0.uppercased()) })
    var initial = NexusConfiguration()
    initial.pinnedEntries = entries
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

/// A real directory, because the drop handler asks the file system whether a URL is one.
private func temporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nexus-drop-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
@Suite("Folder rows")
struct FolderRowTests {
    @Test("A folder entry draws a folder row, named after the folder")
    func drawsRow() async throws {
        let url = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        let (model, _) = makeModel(entries: [.folder(url.path)])
        await model.refresh()

        #expect(model.pinned.count == 1)
        #expect(model.pinned.first?.folder?.path == url.path)
        #expect(model.pinned.first?.folder?.name == url.lastPathComponent)
        // A folder is not an application: it never appears in the flyout's list of items.
        #expect(model.pinnedItems.isEmpty)
    }

    @Test("Dropping a folder from Finder pins it; dropping it twice does not")
    func dropPinsFolder() async throws {
        let url = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        let (model, configuration) = makeModel()

        #expect(model.pinApplications(at: [url]))
        #expect(configuration.configuration.pinnedEntries == [.folder(url.standardizedFileURL.path)])
        #expect(model.pinApplications(at: [url]) == false)
        #expect(configuration.configuration.pinnedEntries.count == 1)
    }

    @Test("Dropping a plain file pins nothing")
    func dropRefusesFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("note.txt")
        try Data().write(to: file)

        let (model, configuration) = makeModel()
        #expect(model.pinApplications(at: [file]) == false)
        #expect(configuration.configuration.pinnedEntries.isEmpty)
    }

    @Test("Remove from Bar takes the folder off and leaves the order alone")
    func unpinFolder() async throws {
        let url = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        let (model, configuration) = makeModel(["a", "b"], entries: [
            .application("a"), .folder(url.path), .application("b"),
        ])
        await model.refresh()

        model.unpinFolder(DockEntry.folder(url.path).id)
        #expect(configuration.configuration.pinnedEntries == [.application("a"), .application("b")])
    }

    @Test("A folder is not a group member, and dropping onto one does not group")
    func foldersDoNotGroup() async throws {
        let url = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: url) }
        let (model, configuration) = makeModel(["a"], entries: [
            .application("a"), .folder(url.path),
        ])
        await model.refresh()

        let folderID = DockEntry.folder(url.path).id
        #expect(model.canGroup("a", with: folderID) == false)
        #expect(model.group("a", with: folderID) == false)
        #expect(configuration.configuration.pinnedEntries.contains(.folder(url.path)))
    }
}

@MainActor
@Suite("The folder stack popover")
struct FolderStackPopoverTests {
    private func folder(_ path: String = "/tmp/Stack") -> SidebarFolder {
        SidebarFolder(path: path, name: "Stack")
    }

    private func item(_ name: String, isDirectory: Bool = false) -> FolderItem {
        FolderItem(
            url: URL(fileURLWithPath: "/tmp/Stack").appendingPathComponent(name),
            name: name,
            isDirectory: isDirectory
        )
    }

    @Test("Opening reads the folder once, and closing forgets what it read")
    func showAndHide() {
        var reads = 0
        let model = FolderStackViewModel()
        model.read = { _ in
            reads += 1
            return .items([self.item("one.txt")])
        }
        model.show(folder())
        #expect(reads == 1)
        #expect(model.listing.items.count == 1)

        var dismissed = false
        model.onDismiss = { dismissed = true }
        model.hide()
        #expect(dismissed)
        #expect(model.folder == nil)
        #expect(model.listing.items.isEmpty)
    }

    @Test("A refusal is kept as a refusal, not flattened into an empty folder")
    func refusalSurvives() {
        let model = FolderStackViewModel()
        model.read = { _ in .refused }
        model.show(folder())
        #expect(model.listing == .refused)
        #expect(model.folder != nil)     // the popover opens, and says why it is empty
    }

    @Test("A folder that is no longer there still opens, and says so")
    func missingSurvives() {
        let model = FolderStackViewModel()
        model.read = { _ in .missing }
        model.show(folder())
        #expect(model.listing == .missing)
        #expect(model.folder != nil)
    }

    @Test("The popover closes when its folder stops being pinned")
    func followsTheDock() {
        let model = FolderStackViewModel()
        model.read = { _ in .items([]) }
        model.show(folder())

        model.update(from: [.folder(folder())])
        #expect(model.folder != nil)

        model.update(from: [])
        #expect(model.folder == nil)
    }

    @Test("Three columns for a short listing, four beyond nine")
    func columns() {
        let model = FolderStackViewModel()
        model.read = { _ in .items((0..<9).map { self.item("file-\($0)") }) }
        model.show(folder())
        #expect(model.columns == 3)

        model.read = { _ in .items((0..<10).map { self.item("file-\($0)") }) }
        model.show(folder())
        #expect(model.columns == 4)
    }
}
