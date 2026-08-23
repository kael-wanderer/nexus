import CoreGraphics
import Foundation
import NexusCore
import Testing

@testable import NexusUI

@MainActor
private func makeModel(
    _ identifiers: [String] = ["a", "b"],
    showMinimized: Bool = true
) -> (SidebarViewModel, ConfigurationController) {
    let service = FakeApplicationService(
        identifiers.map { makeApplication($0, name: $0.uppercased(), running: true) }
    )
    var initial = NexusConfiguration()
    initial.behavior.showMinimizedWindows = showMinimized
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
    // Injected in the composition root; without it every window feature is absent, which is what
    // "Accessibility denied" looks like from here.
    model.activateWindow = { _ in }
    return (model, controller)
}

private func window(
    _ number: CGWindowID,
    of owner: String,
    title: String,
    minimized: Bool
) -> NexusWindow {
    NexusWindow(
        identity: WindowIdentity(
            owner: ApplicationIdentity(bundleIdentifier: owner),
            number: number
        ),
        title: title,
        isMinimized: minimized,
        applicationName: owner.uppercased()
    )
}

@MainActor
@Suite("Minimized windows")
struct MinimizedWindowTests {
    @Test("A window that is minimized gets a row; restoring it takes the row away")
    func appearsAndLeaves() {
        let (model, _) = makeModel()
        model.setAllWindows([
            window(1, of: "a", title: "Draft", minimized: true),
            window(2, of: "b", title: "Console", minimized: false),
        ])
        #expect(model.minimized.map(\.name) == ["Draft"])
        #expect(model.showsMinimizedRows)

        model.setAllWindows([
            window(1, of: "a", title: "Draft", minimized: false),
            window(2, of: "b", title: "Console", minimized: false),
        ])
        #expect(model.minimized.isEmpty)
        #expect(model.showsMinimizedRows == false)
    }

    @Test("A window that closes, or whose application quits, leaves the list")
    func closedWindowLeaves() {
        let (model, _) = makeModel()
        model.setAllWindows([
            window(1, of: "a", title: "Draft", minimized: true),
            window(2, of: "b", title: "Console", minimized: true),
        ])
        #expect(model.minimized.count == 2)

        model.setAllWindows([window(2, of: "b", title: "Console", minimized: true)])
        #expect(model.minimized.map(\.name) == ["Console"])
    }

    @Test("Newest first, and an older one being restored does not reorder the rest")
    func newestFirst() {
        let (model, _) = makeModel()
        model.setAllWindows([window(1, of: "a", title: "First", minimized: true)])
        model.setAllWindows([
            window(1, of: "a", title: "First", minimized: true),
            window(2, of: "b", title: "Second", minimized: true),
        ])
        #expect(model.minimized.map(\.name) == ["Second", "First"])

        model.setAllWindows([
            window(1, of: "a", title: "First", minimized: true),
            window(2, of: "b", title: "Second", minimized: true),
            window(3, of: "a", title: "Third", minimized: true),
        ])
        #expect(model.minimized.map(\.name) == ["Third", "Second", "First"])

        // "Second" is restored: the two either side keep their order.
        model.setAllWindows([
            window(1, of: "a", title: "First", minimized: true),
            window(3, of: "a", title: "Third", minimized: true),
        ])
        #expect(model.minimized.map(\.name) == ["Third", "First"])
    }

    @Test("The section is capped at three rows, and the tail counts the capped number")
    func capsRows() {
        let (model, _) = makeModel()
        let tailWithout = model.tailRowCount
        model.setAllWindows((1...6).map {
            window(CGWindowID($0), of: "a", title: "Window \($0)", minimized: true)
        })

        #expect(model.minimized.count == 6)
        #expect(model.minimizedRowCount == SidebarViewModel.minimizedLimit)
        #expect(model.minimizedRows.count == 3)
        #expect(model.tailRowCount == tailWithout + 3)
    }

    @Test("Switching the setting off gives the slots back")
    func settingReturnsSlots() {
        let (model, configuration) = makeModel()
        model.setAllWindows([
            window(1, of: "a", title: "Draft", minimized: true),
            window(2, of: "b", title: "Console", minimized: true),
        ])
        let withRows = model.tailRowCount
        #expect(model.minimizedRowCount == 2)

        configuration.update { $0.behavior.showMinimizedWindows = false }
        #expect(model.minimizedRowCount == 0)
        #expect(model.showsMinimizedRows == false)
        #expect(model.tailRowCount == withRows - 2)
    }

    @Test("Without the window layer there is no section at all")
    func withoutAccessibility() {
        let (model, _) = makeModel()
        model.activateWindow = nil
        model.setAllWindows([window(1, of: "a", title: "Draft", minimized: true)])
        #expect(model.minimizedRowCount == 0)
        #expect(model.showsMinimizedRows == false)
    }

    @Test("Clicking a row restores through the same path the flyout uses")
    func restoreActivates() {
        let (model, _) = makeModel()
        var activated: [CGWindowID] = []
        model.activateWindow = { activated.append($0.number) }
        model.setAllWindows([window(7, of: "a", title: "Draft", minimized: true)])

        model.restore(model.minimizedRows[0])
        #expect(activated == [7])
    }

    @Test("A window with no title of its own is named after its application")
    func untitledWindow() {
        let (model, _) = makeModel()
        model.setAllWindows([window(1, of: "a", title: "", minimized: true)])
        #expect(model.minimizedRows[0].name == "A")
    }
}
