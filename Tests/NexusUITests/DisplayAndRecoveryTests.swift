import AppKit
import Foundation
import NexusCore
import Testing

@testable import NexusUI

@Suite("Displays")
@MainActor
struct DisplayServiceTests {
    @Test("Every attached screen has a stable UUID identity")
    func identities() {
        let identities = NSScreen.screens.compactMap { DisplayService.identity(of: $0) }
        #expect(identities.count == NSScreen.screens.count)
        #expect(Set(identities).count == identities.count)
        #expect(identities.allSatisfy { !$0.uuid.isEmpty })
    }

    @Test("The same screen resolves to the same identity twice")
    func stableAcrossReads() {
        guard let screen = NSScreen.main else { return }
        #expect(DisplayService.identity(of: screen) == DisplayService.identity(of: screen))
    }

    @Test("A screen can be found again from its identity")
    func roundTrip() {
        guard let screen = NSScreen.main, let identity = DisplayService.identity(of: screen)
        else { return }
        #expect(DisplayService.screen(matching: identity) === screen)
    }

    @Test("The main preference means the menu-bar display, not whichever screen has focus")
    func mainIsTheMenuBarScreen() {
        // NSScreen.main follows the key window, so it wanders onto a second monitor whenever
        // Settings or onboarding opens there. screens.first is the menu-bar display.
        #expect(DisplayService.screen(for: .main) === NSScreen.screens.first)
        #expect(DisplayService.menuBarScreen === NSScreen.screens.first)
    }

    @Test("A disconnected preferred display falls back to the main display")
    func disconnectedFallback() {
        let missing = DisplayPreference.specific("00000000-0000-0000-0000-000000000000")
        #expect(DisplayService.screen(matching: DisplayIdentity(uuid: "00000000-0000-0000-0000-000000000000")) == nil)
        #expect(DisplayService.screen(for: missing) === DisplayService.menuBarScreen)
    }

    @Test("Resolving a preference never mutates the stored preference")
    func preferenceIsNotRewritten() {
        let configuration = ConfigurationController(
            store: InMemoryConfigurationStore(),
            events: EventBus(),
            saveDelay: .zero
        )
        configuration.update { $0.appearance.display = .specific("00000000-0000-0000-0000-000000000000") }
        _ = DisplayService.screen(for: configuration.configuration.appearance.display)
        #expect(configuration.configuration.appearance.display == .specific("00000000-0000-0000-0000-000000000000"))
    }

    @Test("Main and with-pointer preferences always resolve to a real screen")
    func alwaysResolves() {
        #expect(DisplayService.screen(for: .main) != nil)
        #expect(DisplayService.screen(for: .withMouse) != nil)
    }
}

@Suite("Permission revocation recovery")
@MainActor
struct RevocationTests {
    @Test("Revoking Accessibility degrades the flyout to the explain-and-grant screen")
    func flyoutDegrades() async throws {
        let bus = EventBus()
        let permissions = FakePermissions([.accessibility: .granted])
        let identity = ApplicationIdentity(bundleIdentifier: "com.apple.Safari")
        let model = WindowFlyoutViewModel(
            service: FakeWindowService([
                "com.apple.Safari": [
                    NexusWindow(
                        identity: WindowIdentity(owner: identity, number: 1),
                        title: "GitHub",
                        applicationName: "Safari"
                    )
                ]
            ]),
            previewService: FakePreviewService(),
            permissions: permissions,
            events: bus
        )
        model.start()
        defer { model.stop() }
        model.show(identity, name: "Safari")
        await model.reload()
        #expect(model.windows.count == 1)
        #expect(model.showsPermissionRequest == false)

        permissions.statuses[.accessibility] = .denied
        bus.publish(.permissionChanged(.accessibility, .denied))
        try await Task.sleep(for: .milliseconds(150))

        #expect(model.showsPermissionRequest)
        #expect(model.windows.isEmpty)
    }

    @Test("Everything that needs no permission keeps working after a revocation")
    func sidebarUnaffected() async throws {
        let bus = EventBus()
        var initial = NexusConfiguration()
        initial.setPinnedApplications(["com.a", "com.b"])
        let configuration = ConfigurationController(
            store: InMemoryConfigurationStore(initial),
            events: bus,
            saveDelay: .zero
        )
        let model = SidebarViewModel(
            applications: FakeApplicationService([
                makeApplication("com.a", name: "Alpha", running: true),
                makeApplication("com.b", name: "Beta"),
            ]),
            configuration: configuration,
            events: bus
        )
        model.start()
        defer { model.stop() }
        await model.refresh()

        bus.publish(.permissionChanged(.accessibility, .denied))
        try await Task.sleep(for: .milliseconds(100))

        #expect(model.pinned.count == 2)
        model.pin("com.c")
        #expect(configuration.configuration.pinnedApplications == ["com.a", "com.b", "com.c"])
    }

    @Test("Search still returns application results with Accessibility denied")
    func searchUnaffected() async {
        let index = ApplicationIndexSnapshot()
        index.write([
            NexusApplication(
                identity: ApplicationIdentity(bundleIdentifier: "com.apple.Safari"),
                name: "Safari",
                bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
            )
        ])
        let engine = SearchEngine(
            providers: [
                ApplicationSearchProvider(index: index, runningBundleIdentifiers: { [] }),
                WindowSearchProvider(windows: { [] }),   // yields nothing when denied
            ],
            enabled: [.application, .window]
        )
        var last: SearchSnapshot?
        for await snapshot in await engine.search(SearchQuery(text: "safari", token: 1), context: SearchContext()) {
            last = snapshot
        }
        #expect(last?.results.count == 1)
        #expect(last?.results.first?.category == .application)
    }
}

@Suite("Bounded caches")
@MainActor
struct CacheTests {
    @Test("The icon cache is bounded and reuses entries")
    func iconCache() {
        let cache = IconCache(countLimit: 4)
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let first = cache.icon(for: url, size: 32)
        let second = cache.icon(for: url, size: 32)
        #expect(first === second)

        cache.removeAll()
        #expect(cache.icon(for: url, size: 32) !== first)
    }

    @Test("The preview cache never grows without bound")
    func previewCacheBound() async {
        let service = WindowPreviewService()
        // With Screen Recording denied every call returns nil and nothing is stored; with it
        // granted the cache is capped at 32 entries. Either way this must not accumulate.
        for index in 0..<100 {
            _ = await service.preview(
                for: WindowIdentity(
                    owner: ApplicationIdentity(bundleIdentifier: "com.example.app"),
                    number: UInt32(900_000 + index)
                ),
                maxDimension: 320
            )
        }
        await service.invalidateAll()
    }
}
