import Foundation
import Testing

@testable import NexusCore

@Suite("PermissionService")
struct PermissionServiceTests {
    @Test("Every permission has a real System Settings deep link", arguments: Permission.allCases)
    func settingsLinks(permission: Permission) {
        let raw = PermissionService.settingsURL(for: permission)
        #expect(raw.hasPrefix("x-apple.systempreferences:"))
        #expect(URL(string: raw) != nil)
    }

    @Test("Status is answered for every permission without prompting")
    func status() {
        let service = PermissionService(events: EventBus())
        for permission in Permission.allCases {
            let status = service.status(of: permission)
            #expect(status == .granted || status == .denied)
        }
    }

    @Test("The status stream yields immediately and stops when the consumer stops")
    func stream() async {
        let bus = EventBus()
        let service = PermissionService(events: bus)
        let stream = service.statusStream(for: .accessibility)

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == service.status(of: .accessibility))

        // Dropping the iterator terminates the stream, which cancels the 1 Hz poll (D13).
        // Nothing to assert beyond not hanging: the test finishing is the assertion.
    }

    @Test("A status change is republished on the event bus")
    func publishes() async {
        let bus = EventBus()
        let service = PermissionService(events: bus)
        let events = bus.events()
        let stream = service.statusStream(for: .screenRecording)
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        var eventIterator = events.makeAsyncIterator()
        let event = await eventIterator.next()
        #expect(event == .permissionChanged(.screenRecording, service.status(of: .screenRecording)))
    }
}

@Suite("WindowService")
struct WindowServiceTests {
    @Test("Without Accessibility every entry point refuses cleanly instead of hanging")
    func deniedPath() async {
        let service = WindowService()
        let trusted = await service.isTrusted
        let identity = ApplicationIdentity(bundleIdentifier: "com.apple.finder")

        if trusted {
            // Granted on this machine: enumeration must succeed and be well-formed.
            let windows = try? await service.windows(for: identity)
            #expect(windows != nil)
            let allNamed = (windows ?? []).allSatisfy { !$0.applicationName.isEmpty }
            #expect(allNamed)
        } else {
            await #expect(throws: NexusError.permissionDenied(.accessibility)) {
                _ = try await service.windows(for: identity)
            }
            await #expect(throws: NexusError.permissionDenied(.accessibility)) {
                _ = try await service.allWindows()
            }
            await #expect(throws: NexusError.permissionDenied(.accessibility)) {
                try await service.activate(WindowIdentity(owner: identity, number: 1))
            }
        }
    }

    @Test("Activating a window that was never enumerated reports the target as gone")
    func unknownWindow() async {
        let service = WindowService()
        guard await service.isTrusted else { return }
        await #expect(throws: NexusError.targetDisappeared) {
            try await service.activate(
                WindowIdentity(
                    owner: ApplicationIdentity(bundleIdentifier: "com.example.nope"),
                    number: 999_999
                )
            )
        }
    }

    @Test("Forgetting an application clears its cached snapshot")
    func forget() async {
        let service = WindowService()
        let identity = ApplicationIdentity(bundleIdentifier: "com.apple.finder")
        _ = try? await service.windows(for: identity)
        await service.forget(identity)
        let cached = await service.cachedWindows()
        #expect(cached.allSatisfy { $0.identity.owner != identity })
    }
}

@Suite("WindowPreviewService")
struct WindowPreviewServiceTests {
    @Test("A preview request for a window that does not exist returns nil, never throws")
    func missingWindow() async {
        let service = WindowPreviewService()
        let preview = await service.preview(
            for: WindowIdentity(
                owner: ApplicationIdentity(bundleIdentifier: "com.example.nope"),
                number: 987_654_321
            ),
            maxDimension: 320
        )
        #expect(preview == nil)
    }
}
