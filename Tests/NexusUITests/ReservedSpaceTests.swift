import CoreGraphics
import Foundation
import NexusCore
import Testing

@testable import NexusUI

@Suite("Reserved space geometry")
struct ReservedSpaceGeometryTests {
    private let visible = CGRect(x: 0, y: 0, width: 1_440, height: 875)

    @Test("What is left of the screen starts at the far edge of the bar, on every side")
    func available() {
        let left = SidebarLayout.availableFrame(
            besides: CGRect(x: 8, y: 100, width: 64, height: 600),
            in: visible,
            position: .left
        )
        #expect(left == CGRect(x: 72, y: 0, width: 1_368, height: 875))

        let right = SidebarLayout.availableFrame(
            besides: CGRect(x: 1_368, y: 100, width: 64, height: 600),
            in: visible,
            position: .right
        )
        #expect(right == CGRect(x: 0, y: 0, width: 1_368, height: 875))

        let bottom = SidebarLayout.availableFrame(
            besides: CGRect(x: 400, y: 8, width: 600, height: 64),
            in: visible,
            position: .bottom
        )
        #expect(bottom == CGRect(x: 0, y: 72, width: 1_440, height: 803))

        let top = SidebarLayout.availableFrame(
            besides: CGRect(x: 400, y: 803, width: 600, height: 64),
            in: visible,
            position: .top
        )
        #expect(top == CGRect(x: 0, y: 0, width: 1_440, height: 803))
    }

    /// A bar that has slid off the edge (auto-hide parks it there) must not claim space beyond the
    /// screen, or every window on the display looks like it overlaps.
    @Test("A bar parked off the edge takes no more than the screen")
    func availableClamped() {
        let parked = SidebarLayout.availableFrame(
            besides: CGRect(x: -72, y: 100, width: 64, height: 600),
            in: visible,
            position: .left
        )
        #expect(parked == visible)
    }

    private let display = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    private let space = CGRect(x: 72, y: 25, width: 1_368, height: 875)

    @Test("A window overlapping the bar is pushed clear of it and nothing else changes")
    func pushed() {
        let window = CGRect(x: 20, y: 200, width: 800, height: 500)
        let fitted = SidebarLayout.fit(window, into: space, display: display)
        #expect(fitted == CGRect(x: 72, y: 200, width: 800, height: 500))
    }

    @Test("A window too wide to move is resized, and only then")
    func shrunk() {
        let window = CGRect(x: 0, y: 200, width: 1_440, height: 500)
        let fitted = SidebarLayout.fit(window, into: space, display: display)
        #expect(fitted == CGRect(x: 72, y: 200, width: 1_368, height: 500))
    }

    @Test("A window already clear of the bar is left exactly where it is")
    func untouched() {
        let window = CGRect(x: 200, y: 200, width: 400, height: 300)
        #expect(SidebarLayout.fit(window, into: space, display: display) == nil)
    }

    @Test("A full-screen window is not touched")
    func fullScreen() {
        #expect(SidebarLayout.fit(display, into: space, display: display) == nil)
    }

    @Test("A window on another display is that display's business")
    func otherDisplay() {
        let elsewhere = CGRect(x: -1_900, y: 100, width: 800, height: 500)
        #expect(SidebarLayout.fit(elsewhere, into: space, display: display) == nil)
    }

    @Test("Pushing works against each edge, whichever side the space is on")
    func everyEdge() {
        // Space on the left: a window hanging off the right has to come back.
        let spaceLeft = CGRect(x: 0, y: 25, width: 1_368, height: 875)
        let overRight = CGRect(x: 1_000, y: 100, width: 400, height: 300)
        #expect(
            SidebarLayout.fit(overRight, into: spaceLeft, display: display)
                == CGRect(x: 968, y: 100, width: 400, height: 300)
        )

        // Space below: a window over the top edge comes down.
        let spaceBelow = CGRect(x: 0, y: 100, width: 1_440, height: 800)
        let overTop = CGRect(x: 100, y: 20, width: 400, height: 300)
        #expect(
            SidebarLayout.fit(overTop, into: spaceBelow, display: display)
                == CGRect(x: 100, y: 100, width: 400, height: 300)
        )
    }

    @Test("Flipping between Cocoa and Accessibility coordinates is its own inverse")
    func flip() {
        let cocoa = CGRect(x: 40, y: 60, width: 200, height: 100)
        let flipped = ScreenGeometry.flipped(cocoa, primaryHeight: 900)
        #expect(flipped == CGRect(x: 40, y: 740, width: 200, height: 100))
        #expect(ScreenGeometry.flipped(flipped, primaryHeight: 900) == cocoa)
    }
}

@MainActor
private func makeController(
    reserveSpace: Bool = true,
    autoHide: Bool = false,
    trusted: Bool = true,
    windows: [NexusWindow]
) -> (ReservedSpaceController, FakeWindowService, ConfigurationController) {
    var initial = NexusConfiguration()
    initial.behavior.reserveSpace = reserveSpace
    initial.behavior.autoHide = autoHide
    let configuration = ConfigurationController(
        store: InMemoryConfigurationStore(initial),
        events: EventBus(),
        saveDelay: .zero
    )
    let service = FakeWindowService(["com.example.editor": windows])
    let controller = ReservedSpaceController(
        configuration: configuration,
        events: EventBus(),
        windows: service
    )
    controller.isTrusted = { trusted }
    // Work in Accessibility coordinates directly: a zero-height primary display makes the flip
    // the identity, so the fixtures below read as what the code actually compares.
    controller.primaryHeight = { 0 }
    controller.runningApplications = { [ApplicationIdentity(bundleIdentifier: "com.example.editor")] }
    controller.geometries = {
        [ReservedSpaceController.Geometry(
            bar: CGRect(x: 8, y: -700, width: 64, height: 600),
            visible: CGRect(x: 0, y: -875, width: 1_440, height: 875),
            display: CGRect(x: 0, y: -900, width: 1_440, height: 900),
            position: .left
        )]
    }
    return (controller, service, configuration)
}

private func window(_ number: CGWindowID, _ frame: CGRect, minimized: Bool = false) -> NexusWindow {
    NexusWindow(
        identity: WindowIdentity(
            owner: ApplicationIdentity(bundleIdentifier: "com.example.editor"),
            number: number
        ),
        title: "Window \(number)",
        isMinimized: minimized,
        frame: frame
    )
}

@MainActor
@Suite("Reserved space controller")
struct ReservedSpaceControllerTests {
    private var geometry: ReservedSpaceController.Geometry {
        ReservedSpaceController.Geometry(
            bar: CGRect(x: 8, y: -700, width: 64, height: 600),
            visible: CGRect(x: 0, y: -875, width: 1_440, height: 875),
            display: CGRect(x: 0, y: -900, width: 1_440, height: 900),
            position: .left
        )
    }

    @Test("An overlapping window is moved off the bar")
    func moves() async {
        let (controller, service, _) = makeController(windows: [window(1, CGRect(x: 10, y: 100, width: 600, height: 400))])

        await controller.sweep([geometry])

        let set = await service.framesSet
        #expect(set.count == 1)
        #expect(set.first?.frame == CGRect(x: 72, y: 100, width: 600, height: 400))
    }

    @Test("With the setting off, or auto-hide on, or Accessibility missing, nothing is touched")
    func gated() async {
        for controller in [
            makeController(reserveSpace: false, windows: [window(1, CGRect(x: 10, y: 100, width: 600, height: 400))]),
            makeController(autoHide: true, windows: [window(1, CGRect(x: 10, y: 100, width: 600, height: 400))]),
            makeController(trusted: false, windows: [window(1, CGRect(x: 10, y: 100, width: 600, height: 400))]),
        ] {
            #expect(controller.0.isEnabled == false)
            var observed: [Bool] = []
            controller.0.observeGeometry = { observed.append($0) }
            controller.0.apply()
            #expect(observed.isEmpty)
            let set = await controller.1.framesSet
            #expect(set.isEmpty)
        }
    }

    @Test("A window already clear of the bar, and a minimised one, are left alone")
    func leavesAlone() async {
        let (controller, service, _) = makeController(windows: [
            window(1, CGRect(x: 200, y: 100, width: 600, height: 400)),
            window(2, CGRect(x: 10, y: 100, width: 600, height: 400), minimized: true),
        ])

        await controller.sweep([geometry])

        let set = await service.framesSet
        #expect(set.isEmpty)
    }

    /// The feedback loop this protects against: an application that repositions its own window
    /// gets moved, moves back, gets moved… Four attempts and Nexus stops.
    @Test("An application that keeps putting its window back wins")
    func stopsFighting() async {
        let (controller, service, _) = makeController(windows: [window(1, CGRect(x: 10, y: 100, width: 600, height: 400))])
        await service.putBack(1)

        for _ in 0..<8 { await controller.sweep([geometry]) }

        let set = await service.framesSet
        #expect(set.count == ReservedSpaceController.maximumAttempts)
    }

    @Test("A window whose application refuses the move is not asked twice")
    func refusalIsFinal() async {
        let (controller, service, _) = makeController(windows: [window(1, CGRect(x: 10, y: 100, width: 600, height: 400))])
        await service.refuse(1)

        for _ in 0..<5 { await controller.sweep([geometry]) }

        let set = await service.framesSet
        #expect(set.count == 1)
    }

    @Test("Switching the setting on installs the move observers, off removes them")
    func observers() async {
        let (controller, _, configuration) = makeController(windows: [])
        var observed: [Bool] = []
        controller.observeGeometry = { observed.append($0) }

        controller.apply()
        #expect(observed == [true])

        configuration.update { $0.behavior.reserveSpace = false }
        controller.apply()
        #expect(observed == [true, false])
    }
}

@MainActor
@Suite("Reserved space with a bar on every display")
struct ReservedSpaceMultiDisplayTests {
    /// Two 1440-wide displays side by side, each with a 64 pt bar on its left edge, in Accessibility
    /// coordinates (the fixtures above use a zero primary height, so the flip is the identity).
    private var bars: [ReservedSpaceController.Geometry] {
        [
            ReservedSpaceController.Geometry(
                bar: CGRect(x: 8, y: -700, width: 64, height: 600),
                visible: CGRect(x: 0, y: -875, width: 1_440, height: 875),
                display: CGRect(x: 0, y: -900, width: 1_440, height: 900),
                position: .left
            ),
            ReservedSpaceController.Geometry(
                bar: CGRect(x: 1_448, y: -700, width: 64, height: 600),
                visible: CGRect(x: 1_440, y: -875, width: 1_440, height: 875),
                display: CGRect(x: 1_440, y: -900, width: 1_440, height: 900),
                position: .left
            ),
        ]
    }

    @Test("A window over the second display's bar is pushed off that bar, and stays on it")
    func secondDisplay() async {
        let (controller, service, _) = makeController(
            windows: [window(1, CGRect(x: 1_450, y: 100, width: 600, height: 400))]
        )
        controller.geometries = { self.bars }

        await controller.sweep(bars)

        let set = await service.framesSet
        #expect(set.count == 1)
        #expect(set.first?.frame == CGRect(x: 1_512, y: 100, width: 600, height: 400))
    }

    @Test("A window clear of both bars is left where it is")
    func untouched() async {
        let (controller, service, _) = makeController(
            windows: [window(2, CGRect(x: 1_600, y: 100, width: 600, height: 400))]
        )
        controller.geometries = { self.bars }

        await controller.sweep(bars)

        #expect(await service.framesSet.isEmpty)
    }

    @Test("One sweep clears both displays")
    func bothDisplays() async {
        let (controller, service, _) = makeController(
            windows: [
                window(3, CGRect(x: 10, y: 100, width: 600, height: 400)),
                window(4, CGRect(x: 1_450, y: 100, width: 600, height: 400)),
            ]
        )
        controller.geometries = { self.bars }

        await controller.sweep(bars)

        let moved = await service.framesSet
        #expect(moved.count == 2)
        #expect(moved.contains { $0.frame.minX == 72 })
        #expect(moved.contains { $0.frame.minX == 1_512 })
    }

    @Test("No bars on screen means nothing is swept and no observers are installed")
    func noBars() async {
        let (controller, service, _) = makeController(
            windows: [window(5, CGRect(x: 10, y: 100, width: 600, height: 400))]
        )
        controller.geometries = { [] }
        var observed: [Bool] = []
        controller.observeGeometry = { observed.append($0) }

        controller.apply()

        // Same shape as the gated cases: nothing to keep clear of, so no observers are installed
        // and no window is touched.
        #expect(observed.isEmpty)
        #expect(await service.framesSet.isEmpty)
    }
}
