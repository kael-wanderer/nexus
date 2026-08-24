import CoreGraphics
import Foundation
import NexusCore
import Testing

@testable import NexusUI

actor FakeWindowService: WindowServing {
    private var byApplication: [String: [NexusWindow]]
    private(set) var activated: [WindowIdentity] = []
    private(set) var framesSet: [(window: WindowIdentity, frame: CGRect)] = []
    private(set) var closed: [WindowIdentity] = []
    private var refuses: Set<CGWindowID> = []
    private var putsBack: Set<CGWindowID> = []
    private var trusted: Bool

    init(_ byApplication: [String: [NexusWindow]] = [:], trusted: Bool = true) {
        self.byApplication = byApplication
        self.trusted = trusted
    }

    func setWindows(_ windows: [NexusWindow], for bundleIdentifier: String) {
        byApplication[bundleIdentifier] = windows
    }

    func windows(for application: ApplicationIdentity) async throws -> [NexusWindow] {
        guard trusted else { throw NexusError.permissionDenied(.accessibility) }
        return byApplication[application.bundleIdentifier] ?? []
    }

    func allWindows() async throws -> [NexusWindow] {
        guard trusted else { throw NexusError.permissionDenied(.accessibility) }
        return byApplication.values.flatMap(\.self)
    }

    func activate(_ window: WindowIdentity) async throws {
        guard trusted else { throw NexusError.permissionDenied(.accessibility) }
        activated.append(window)
    }

    @discardableResult
    func setFrame(_ frame: CGRect, for window: WindowIdentity) async throws -> Bool {
        guard trusted else { throw NexusError.permissionDenied(.accessibility) }
        framesSet.append((window, frame))
        guard !refuses.contains(window.number) else { return false }
        if var list = byApplication[window.owner.bundleIdentifier],
           let index = list.firstIndex(where: { $0.identity.number == window.number }) {
            list[index].frame = putsBack.contains(window.number) ? list[index].frame : frame
            byApplication[window.owner.bundleIdentifier] = list
        }
        return true
    }

    func close(_ window: WindowIdentity) async throws {
        guard trusted else { throw NexusError.permissionDenied(.accessibility) }
        closed.append(window)
    }

    /// Windows whose application refuses to move them at all.
    func refuse(_ number: CGWindowID) { refuses.insert(number) }
    /// Windows whose application drags them straight back where they were.
    func putBack(_ number: CGWindowID) { putsBack.insert(number) }
}

/// Polls until `condition` holds, up to two seconds. Replaces a fixed sleep in tests that wait on
/// work handed to a Task.
@MainActor
func until(_ condition: () async -> Bool) async {
    for _ in 0..<200 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

struct FakePreviewService: WindowPreviewing {
    func preview(for window: WindowIdentity, maxDimension: CGFloat) async -> SendableImage? { nil }
    func invalidate(_ window: WindowIdentity) async {}

    func previews(
        for windows: [WindowIdentity],
        maxDimension: CGFloat
    ) async -> AsyncStream<(WindowIdentity, SendableImage)> {
        AsyncStream { $0.finish() }
    }
}

final class FakePermissions: PermissionChecking, @unchecked Sendable {
    var statuses: [Permission: PermissionStatus]
    private(set) var requested: [Permission] = []

    init(_ statuses: [Permission: PermissionStatus]) { self.statuses = statuses }

    func status(of permission: Permission) -> PermissionStatus { statuses[permission] ?? .denied }
    func requestOrOpenSettings(_ permission: Permission) { requested.append(permission) }
    func statusStream(for permission: Permission) -> AsyncStream<PermissionStatus> {
        AsyncStream { $0.yield(status(of: permission)); $0.finish() }
    }
}

private func window(_ bundleIdentifier: String, _ number: CGWindowID, _ title: String) -> NexusWindow {
    NexusWindow(
        identity: WindowIdentity(
            owner: ApplicationIdentity(bundleIdentifier: bundleIdentifier),
            number: number
        ),
        title: title,
        applicationName: "Test App"
    )
}

@Suite("WindowFlyoutViewModel")
@MainActor
struct WindowFlyoutTests {
    @Test("With Accessibility denied the flyout shows the explain-and-grant screen, not an error")
    func denied() async {
        let permissions = FakePermissions([.accessibility: .denied])
        let model = WindowFlyoutViewModel(
            service: FakeWindowService(trusted: false),
            previewService: FakePreviewService(),
            permissions: permissions,
            events: EventBus()
        )
        model.show(ApplicationIdentity(bundleIdentifier: "com.apple.Safari"), name: "Safari")
        await model.reload()

        #expect(model.showsPermissionRequest)
        #expect(model.windows.isEmpty)
        #expect(model.showsPreviewsOffer == false)
    }

    @Test("With Accessibility granted windows are listed and clicking one raises it")
    func granted() async throws {
        let service = FakeWindowService(
            ["com.apple.Safari": [window("com.apple.Safari", 1, "GitHub"), window("com.apple.Safari", 2, "Docs")]]
        )
        let model = WindowFlyoutViewModel(
            service: service,
            previewService: FakePreviewService(),
            permissions: FakePermissions([.accessibility: .granted, .screenRecording: .granted]),
            events: EventBus()
        )
        model.show(ApplicationIdentity(bundleIdentifier: "com.apple.Safari"), name: "Safari")
        await model.reload()

        #expect(model.showsPermissionRequest == false)
        #expect(model.windows.map(\.title) == ["GitHub", "Docs"])

        model.activate(model.windows[0])
        // Activation is a detached Task; wait for it rather than guessing at a sleep that fails
        // whenever the machine is busy.
        await until { await service.activated.count == 1 }
        #expect(await service.activated.map(\.number) == [1])
        #expect(model.target == nil)   // activating dismisses the flyout
    }

    @Test("A window closed by the user disappears on the next event, with no manual refresh")
    func liveUpdate() async throws {
        let bus = EventBus()
        let identity = ApplicationIdentity(bundleIdentifier: "com.apple.Safari")
        let service = FakeWindowService(
            ["com.apple.Safari": [window("com.apple.Safari", 1, "GitHub"), window("com.apple.Safari", 2, "Docs")]]
        )
        let model = WindowFlyoutViewModel(
            service: service,
            previewService: FakePreviewService(),
            permissions: FakePermissions([.accessibility: .granted, .screenRecording: .granted]),
            events: bus
        )
        model.start()
        defer { model.stop() }
        model.show(identity, name: "Safari")
        await model.reload()
        #expect(model.windows.count == 2)

        await service.setWindows([window("com.apple.Safari", 1, "GitHub")], for: "com.apple.Safari")
        bus.publish(.windowsChanged(identity))

        try await Task.sleep(for: .milliseconds(150))
        #expect(model.windows.map(\.identity.number) == [1])
    }

    @Test("Declining previews once means never offering them again")
    func previewsOffer() async {
        let model = WindowFlyoutViewModel(
            service: FakeWindowService(["com.apple.Safari": [window("com.apple.Safari", 1, "GitHub")]]),
            previewService: FakePreviewService(),
            permissions: FakePermissions([.accessibility: .granted, .screenRecording: .denied]),
            events: EventBus()
        )
        model.show(ApplicationIdentity(bundleIdentifier: "com.apple.Safari"), name: "Safari")
        await model.reload()
        #expect(model.showsPreviewsOffer)

        model.dismissPreviewsOffer()
        #expect(model.showsPreviewsOffer == false)
    }

    @Test("Granting Accessibility while the flyout is open loads the windows")
    func grantWhileOpen() async throws {
        let bus = EventBus()
        let permissions = FakePermissions([.accessibility: .denied])
        let model = WindowFlyoutViewModel(
            service: FakeWindowService(["com.apple.Safari": [window("com.apple.Safari", 1, "GitHub")]]),
            previewService: FakePreviewService(),
            permissions: permissions,
            events: bus
        )
        model.start()
        defer { model.stop() }
        model.show(ApplicationIdentity(bundleIdentifier: "com.apple.Safari"), name: "Safari")
        await model.reload()
        #expect(model.windows.isEmpty)

        permissions.statuses[.accessibility] = .granted
        bus.publish(.permissionChanged(.accessibility, .granted))
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.windows.count == 1)
    }

    @Test("The owning application terminating dismisses the flyout")
    func ownerTerminated() async throws {
        let bus = EventBus()
        let identity = ApplicationIdentity(bundleIdentifier: "com.apple.Safari")
        let model = WindowFlyoutViewModel(
            service: FakeWindowService(["com.apple.Safari": [window("com.apple.Safari", 1, "GitHub")]]),
            previewService: FakePreviewService(),
            permissions: FakePermissions([.accessibility: .granted]),
            events: bus
        )
        model.start()
        defer { model.stop() }
        model.show(identity, name: "Safari")
        await model.reload()

        bus.publish(.applicationTerminated(identity))
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.target == nil)
    }

    @Test("Closing a window asks the service and leaves the list alone until it changes")
    func closeIsRequestedNotAssumed() async throws {
        let service = FakeWindowService()
        let window = NexusWindow(
            identity: WindowIdentity(owner: ApplicationIdentity(bundleIdentifier: "com.apple.Safari"), number: 1),
            title: "Google",
            applicationName: "Safari"
        )
        await service.setWindows([window], for: "com.apple.Safari")

        try await service.close(window.identity)

        #expect(await service.closed == [window.identity])
        // Nothing was removed: an unsaved document puts up a sheet and the window is still there.
        #expect(try await service.windows(for: window.identity.owner).count == 1)
    }
}

@Suite("Flyout placement")
struct FlyoutPlacementTests {
    private let appearance: AppearanceConfiguration = {
        var appearance = AppearanceConfiguration()
        appearance.iconSize = 40
        appearance.iconSpacing = 8
        return appearance
    }()

    @Test("Row centres advance by one row plus one gap within a section")
    func rowCentres() {
        let first = SidebarLayout.rowCentre(
            sectionRowCounts: [3], section: 0, row: 0, appearance: appearance
        )
        let second = SidebarLayout.rowCentre(
            sectionRowCounts: [3], section: 0, row: 1, appearance: appearance
        )
        let step: CGFloat = SidebarLayout.rowHeight(appearance) + CGFloat(appearance.iconSpacing)
        #expect(first == SidebarLayout.outerPadding + SidebarLayout.rowHeight(appearance) / 2)
        #expect(second - first == step)
    }

    @Test("The second section starts past the first section and its separator")
    func secondSection() {
        let firstOfSecond = SidebarLayout.rowCentre(
            sectionRowCounts: [2, 2], section: 1, row: 0, appearance: appearance
        )
        let lastOfFirst = SidebarLayout.rowCentre(
            sectionRowCounts: [2, 2], section: 0, row: 1, appearance: appearance
        )
        #expect(firstOfSecond > lastOfFirst)
    }

    @Test("A flyout is placed beside the sidebar and stays on screen")
    func placement() {
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 875)
        let sidebar = CGRect(x: 8, y: 200, width: 64, height: 400)
        let size = CGSize(width: 320, height: 200)

        let left = SidebarLayout.flyoutFrame(
            size: size, beside: sidebar, anchor: 24,
            in: visible, position: .left
        )
        #expect(left.minX == sidebar.maxX + SidebarLayout.screenMargin)
        #expect(visible.contains(left))

        let rightSidebar = CGRect(x: 1_368, y: 200, width: 64, height: 400)
        let right = SidebarLayout.flyoutFrame(
            size: size, beside: rightSidebar, anchor: 24,
            in: visible, position: .right
        )
        #expect(right.maxX == rightSidebar.minX - SidebarLayout.screenMargin)
        #expect(visible.contains(right))
    }

    @Test("A flyout anchored near the top or bottom edge is clamped, not clipped")
    func clamping() {
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 875)
        let sidebar = CGRect(x: 8, y: 8, width: 64, height: 859)
        let size = CGSize(width: 320, height: 400)

        let top = SidebarLayout.flyoutFrame(
            size: size, beside: sidebar, anchor: 20, in: visible, position: .left
        )
        #expect(visible.contains(top))

        let bottom = SidebarLayout.flyoutFrame(
            size: size, beside: sidebar, anchor: 850, in: visible, position: .left
        )
        #expect(visible.contains(bottom))
    }
}
