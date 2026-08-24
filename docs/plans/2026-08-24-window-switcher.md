# Window Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A full-screen grid of every window on the machine, opened by a global shortcut, that filters, sorts, groups, activates, closes, and turns a selection into a dock group — plus a Shortcuts tab that finally holds every global shortcut in one place.

**Architecture:** Nothing new underneath. `WindowService` already enumerates and activates windows; it gains `close`. `WindowPreviewService` already captures thumbnails one at a time; it gains a bulk path that fetches `SCShareableContent` once and captures at most four windows at a time. On top sits one `@Observable` view model (`SwitcherViewModel`), one SwiftUI view, and one panel controller modelled line-for-line on `SearchPanelController` — the existing pattern for a panel that must take the keyboard and give it back.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSPanel`), ScreenCaptureKit, Carbon HotKey API, Swift Testing (`import Testing`, `@Test`, `#expect`).

**Spec:** `docs/design/window-switcher.md`

## Global Constraints

- Swift tools 6.0, platform floor **macOS 14** (`Package.swift`). No new dependencies — the package has none and gains none.
- Targets: `NexusCore` (no UI imports), `NexusUI` (depends on NexusCore), `NexusApp` (composition root). Tests: `NexusCoreTests`, `NexusUITests`.
- **Zero warnings.** `swift build` and `swift test` must both be clean; a warning is a failed task.
- Every new stored configuration field decodes with `decodeIfPresent(...) ?? default` in the hand-written `init(from:)` — a synthesised decoder resets every sibling field on upgrade (D67).
- All user-facing strings go through `String(localized:)`.
- Comments explain **why**, not what, and match the existing voice: full sentences, references to `design/…` sections and `D<number>` decisions where a decision was made.
- No AX traffic on a timer. Enumeration happens on user events only (§65).
- Accessibility gates the window list; Screen Recording gates thumbnails. Neither denial is ever an alert (`design/mvp.md` §3, D5) — the switcher's in-panel Screen Recording offer is the one documented exception (spec §5).
- Run tests with `swift test` from the repo root. Build the app with `make build`; `make run` launches it.
- Commit after every task, message in the repo's voice (`feat:` / `fix:` / `docs:`, lowercase subject, a body that says why).

---

### Task 1: Configuration — shortcut, grouping, sort, thumbnails

**Files:**
- Modify: `Sources/NexusCore/Configuration/NexusConfiguration.swift`
- Test: `Tests/NexusCoreTests/ConfigurationTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum WindowSwitcherGrouping: String, Codable, Sendable, CaseIterable { case flat, application, display }`
  - `enum WindowSwitcherSort: String, Codable, Sendable, CaseIterable { case recent, application, title }`
  - `KeyboardShortcut.windowSwitcherDefault` — `⌃⌥W`
  - `GeneralConfiguration.windowSwitcherShortcut: KeyboardShortcut?`
  - `BehaviorConfiguration.windowSwitcherGrouping`, `.windowSwitcherSort`, `.windowSwitcherSortReversed`, `.windowSwitcherThumbnails`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/NexusCoreTests/ConfigurationTests.swift`, inside the existing suite:

```swift
@Test("Window switcher defaults")
func windowSwitcherDefaults() {
    let configuration = NexusConfiguration()
    #expect(configuration.general.windowSwitcherShortcut == .windowSwitcherDefault)
    #expect(configuration.behavior.windowSwitcherGrouping == .flat)
    #expect(configuration.behavior.windowSwitcherSort == .recent)
    #expect(configuration.behavior.windowSwitcherSortReversed == false)
    #expect(configuration.behavior.windowSwitcherThumbnails == true)
}

@Test("The switcher shortcut is a valid, non-colliding combination")
func windowSwitcherShortcutIsValid() {
    let shortcut = KeyboardShortcut.windowSwitcherDefault
    #expect(shortcut.isValid)
    #expect(shortcut != .optionSpace)
    #expect(shortcut != .focusBarDefault)
}

@Test("A file written before the switcher existed keeps its other fields")
func windowSwitcherTolerantDecode() throws {
    // A behavior section from an earlier version: no switcher keys at all.
    let json = Data("""
    {"autoHide": true, "groupCapacity": 16}
    """.utf8)
    let behavior = try JSONDecoder().decode(BehaviorConfiguration.self, from: json)
    #expect(behavior.autoHide == true)
    #expect(behavior.groupCapacity == 16)
    #expect(behavior.windowSwitcherGrouping == .flat)
    #expect(behavior.windowSwitcherSort == .recent)
    #expect(behavior.windowSwitcherThumbnails == true)
}

@Test("Switcher preferences round-trip through the store")
func windowSwitcherRoundTrip() throws {
    let store = ConfigurationStore(defaults: makeDefaults())
    var configuration = NexusConfiguration()
    configuration.behavior.windowSwitcherGrouping = .display
    configuration.behavior.windowSwitcherSort = .title
    configuration.behavior.windowSwitcherSortReversed = true
    configuration.general.windowSwitcherShortcut = nil

    store.save(configuration)
    let loaded = store.load()
    #expect(loaded.behavior.windowSwitcherGrouping == .display)
    #expect(loaded.behavior.windowSwitcherSort == .title)
    #expect(loaded.behavior.windowSwitcherSortReversed == true)
    #expect(loaded.general.windowSwitcherShortcut == nil)
}
```

If `store.save(_:)` is not the store's actual write method, use whatever the neighbouring `roundTrip()` test in the same file uses — copy that line verbatim rather than inventing one.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ConfigurationTests`
Expected: FAIL — `value of type 'GeneralConfiguration' has no member 'windowSwitcherShortcut'`.

- [ ] **Step 3: Add the enums and the default shortcut**

In `Sources/NexusCore/Configuration/NexusConfiguration.swift`, beside the other stored enums (after `ClickBehavior`):

```swift
/// How the switcher's grid is divided up (M25).
public enum WindowSwitcherGrouping: String, Codable, Sendable, CaseIterable {
    case flat
    case application
    case display
}

/// What orders the switcher's cards (M25). `recent` is the order applications were last
/// activated, which is the order a switcher is normally reached for.
public enum WindowSwitcherSort: String, Codable, Sendable, CaseIterable {
    case recent
    case application
    case title
}
```

In `KeyboardShortcut`, beside `focusBarDefault`:

```swift
/// `⌃⌥W` — the window switcher (M25). `⌥Space` is the palette and `⌃⌥Space` is the bar (D101);
/// `⌘Tab` and `⌃↓` belong to the system and never reach a Carbon hotkey.
public static let windowSwitcherDefault = KeyboardShortcut(
    keyCode: 13,                                     // kVK_ANSI_W
    modifiers: controlKey | optionKey
)
```

- [ ] **Step 4: Add the stored fields**

In `GeneralConfiguration`, beside `focusBarShortcut`:

```swift
/// The window switcher's shortcut (M25). `nil` switches the feature off entirely — there is no
/// other way in, by design: a switcher reached with the pointer is the bar.
public var windowSwitcherShortcut: KeyboardShortcut? = .windowSwitcherDefault
```

and in its `init(from:)`:

```swift
windowSwitcherShortcut = try container.decodeIfPresent(
    KeyboardShortcut.self,
    forKey: .windowSwitcherShortcut
) ?? .windowSwitcherDefault
```

In `BehaviorConfiguration`:

```swift
/// How the switcher opened last time (M25). Remembered rather than reset, because a grouping is
/// a way of working, not a one-off.
public var windowSwitcherGrouping: WindowSwitcherGrouping = .flat
public var windowSwitcherSort: WindowSwitcherSort = .recent
public var windowSwitcherSortReversed = false
/// Off skips ScreenCaptureKit entirely: icons only, and no permission ever asked for.
public var windowSwitcherThumbnails = true
```

and in its `init(from:)`:

```swift
windowSwitcherGrouping = try container.decodeIfPresent(
    WindowSwitcherGrouping.self,
    forKey: .windowSwitcherGrouping
) ?? .flat
windowSwitcherSort = try container.decodeIfPresent(WindowSwitcherSort.self, forKey: .windowSwitcherSort) ?? .recent
windowSwitcherSortReversed = try container.decodeIfPresent(Bool.self, forKey: .windowSwitcherSortReversed) ?? false
windowSwitcherThumbnails = try container.decodeIfPresent(Bool.self, forKey: .windowSwitcherThumbnails) ?? true
```

If either struct declares an explicit `CodingKeys` enum, add the four cases to it. If it relies on the synthesised one, the stored property names are the keys and nothing else is needed.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter ConfigurationTests`
Expected: PASS, no warnings.

- [ ] **Step 6: Commit**

```bash
git add Sources/NexusCore/Configuration/NexusConfiguration.swift Tests/NexusCoreTests/ConfigurationTests.swift
git commit -m "feat: the switcher's shortcut, grouping and sort are configuration

M25. ⌃⌥W by default, and the grouping and sort the switcher was last
left in, so it opens the way it was closed. Tolerant decode, as with
every field added since D67."
```

---

### Task 2: `WindowService.close`

**Files:**
- Modify: `Sources/NexusCore/Windows/WindowService.swift`
- Modify: whichever test file declares `FakeWindowService` (`grep -rn "actor FakeWindowService" Tests`)
- Test: `Tests/NexusUITests/WindowFlyoutTests.swift` — the real `WindowService` talks to other processes, so the contract is tested through the fake.

**Interfaces:**
- Consumes: `WindowIdentity`, `NexusError`, `AX` from Task 0 (existing code).
- Produces: `WindowServing.close(_ window: WindowIdentity) async throws` — a new protocol requirement, implemented by `WindowService` and by every fake.

- [ ] **Step 1: Write the failing test**

`FakeWindowService` is the only implementation a test can reach — the real one talks to other processes. Add to the fake (in the same file it is already declared in):

```swift
private(set) var closed: [WindowIdentity] = []

func close(_ window: WindowIdentity) async throws {
    guard trusted else { throw NexusError.permissionDenied(.accessibility) }
    closed.append(window)
}
```

Then, in `Tests/NexusUITests/WindowFlyoutTests.swift`:

```swift
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
    #expect(await service.windows(for: window.identity.owner).count == 1)
}
```

Match `ApplicationIdentity`'s real initialiser: `grep -n "public init" Sources/NexusCore/Models/Identities.swift` and use it exactly.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter closeIsRequestedNotAssumed`
Expected: FAIL — `WindowServing` has no member `close`, or the fake does not conform.

- [ ] **Step 3: Add `close` to the protocol and the service**

In `Sources/NexusCore/Windows/WindowService.swift`, add to the protocol:

```swift
/// Presses the window's own close button. Nothing is removed from the snapshot here: a window
/// with unsaved work puts up a sheet and stays, and the list must show what is actually there.
func close(_ window: WindowIdentity) async throws
```

and to the actor, beside `activate`:

```swift
public func close(_ window: WindowIdentity) throws {
    guard checkTrust() else { throw NexusError.permissionDenied(.accessibility) }
    guard let element = elements[window.owner]?[window.number] else {
        throw NexusError.targetDisappeared
    }
    // A window without a close button — a panel, a sheet's parent — is not an error worth
    // showing anybody: there is simply nothing to press.
    guard let button: AXUIElement = try AX.value(element, kAXCloseButtonAttribute) else {
        Log.windows.notice("No close button on window \(window.number, privacy: .public)")
        return
    }
    let pressed = AX.perform(button, kAXPressAction)
    Log.windows.notice("Close \(pressed ? "succeeded" : "failed", privacy: .public) for window \(window.number, privacy: .public)")
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test`
Expected: PASS — every existing test still passes, because the protocol addition is implemented by both the real service and the fake. If another fake in the test targets conforms to `WindowServing`, give it the same two-line implementation.

- [ ] **Step 5: Commit**

```bash
git add Sources/NexusCore/Windows/WindowService.swift Tests
git commit -m "feat: a window can be closed from its own card

M25. Presses the AX close button and says nothing else: the snapshot is
not edited optimistically, because a window with unsaved work puts up a
sheet and stays exactly where it was."
```

---

### Task 3: Bulk thumbnails

**Files:**
- Modify: `Sources/NexusCore/Windows/WindowPreviewService.swift`
- Test: `Tests/NexusCoreTests/WindowPreviewBatchTests.swift` (create)

**Interfaces:**
- Consumes: `SendableImage`, `WindowIdentity`.
- Produces:
  - `WindowPreviewing.previews(for windows: [WindowIdentity], maxDimension: CGFloat) async -> AsyncStream<(WindowIdentity, SendableImage)>`
  - `enum PreviewBatch { static func run<T>(_ items: [T], maxInFlight: Int, work: @Sendable @escaping (T) async -> Void) async }` — the concurrency cap, extracted so it can be tested without ScreenCaptureKit.

- [ ] **Step 1: Write the failing test**

Create `Tests/NexusCoreTests/WindowPreviewBatchTests.swift`:

```swift
import Foundation
import Testing

@testable import NexusCore

@Suite("Bulk previews")
struct WindowPreviewBatchTests {
    /// Counts how many pieces of work overlap, which is the only thing the cap promises.
    actor Concurrency {
        private var current = 0
        private(set) var peak = 0

        func enter() { current += 1; peak = max(peak, current) }
        func leave() { current -= 1 }
    }

    @Test("Never more than the cap in flight, and everything still runs")
    func capped() async {
        let counter = Concurrency()
        let done = Counter()

        await PreviewBatch.run(Array(1...20), maxInFlight: 4) { _ in
            await counter.enter()
            try? await Task.sleep(for: .milliseconds(5))
            await counter.leave()
            await done.increment()
        }

        #expect(await counter.peak <= 4)
        #expect(await done.value == 20)
    }

    @Test("An empty batch finishes immediately")
    func empty() async {
        let done = Counter()
        await PreviewBatch.run([Int](), maxInFlight: 4) { _ in await done.increment() }
        #expect(await done.value == 0)
    }

    actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter "Bulk previews"`
Expected: FAIL — `cannot find 'PreviewBatch' in scope`.

- [ ] **Step 3: Implement the cap**

In `Sources/NexusCore/Windows/WindowPreviewService.swift`:

```swift
/// Runs a batch with a ceiling on how much of it happens at once.
///
/// A grid of twenty windows asking ScreenCaptureKit for twenty captures at the same moment is
/// slower than four at a time, not faster: the work is one compositor's, and the queue is where
/// it ends up either way (M25).
enum PreviewBatch {
    static func run<T: Sendable>(
        _ items: [T],
        maxInFlight: Int,
        work: @Sendable @escaping (T) async -> Void
    ) async {
        guard !items.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var next = 0
            let limit = max(1, min(maxInFlight, items.count))
            while next < limit {
                let item = items[next]
                group.addTask { await work(item) }
                next += 1
            }
            while await group.next() != nil {
                guard next < items.count else { continue }
                let item = items[next]
                group.addTask { await work(item) }
                next += 1
            }
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter "Bulk previews"`
Expected: PASS.

- [ ] **Step 5: Add the bulk entry point to the service**

Add to the `WindowPreviewing` protocol:

```swift
/// Every thumbnail for one grid, delivered as each lands rather than all at the end (M25).
/// One `SCShareableContent` fetch serves the whole batch: it is the expensive part of a capture,
/// and paying it per window is what made the grid unusable at twelve.
func previews(
    for windows: [WindowIdentity],
    maxDimension: CGFloat
) async -> AsyncStream<(WindowIdentity, SendableImage)>
```

Implement it in the actor:

```swift
public func previews(
    for windows: [WindowIdentity],
    maxDimension: CGFloat
) async -> AsyncStream<(WindowIdentity, SendableImage)> {
    let (stream, continuation) = AsyncStream<(WindowIdentity, SendableImage)>.makeStream()

    guard CGPreflightScreenCaptureAccess() else {
        continuation.finish()
        return stream
    }

    // Cached windows are answered before anything is fetched: reopening the switcher twice in
    // five seconds should cost nothing at all.
    var pending: [WindowIdentity] = []
    for window in windows {
        if let entry = cache[window.number], Date().timeIntervalSince(entry.capturedAt) < Self.timeToLive {
            continuation.yield((window, entry.image))
        } else {
            pending.append(window)
        }
    }
    guard !pending.isEmpty else {
        continuation.finish()
        return stream
    }

    let content: SCShareableContent
    do {
        content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    } catch {
        // A denial, or a fetch that raced a display change: normal state, never an alert (D48).
        Log.windows.notice("Bulk previews unavailable: \(String(describing: error), privacy: .public)")
        continuation.finish()
        return stream
    }

    let targets = pending.compactMap { identity -> (WindowIdentity, SCWindow)? in
        guard let window = content.windows.first(where: { $0.windowID == identity.number }) else { return nil }
        return (identity, window)
    }

    Task { [weak self] in
        await PreviewBatch.run(targets, maxInFlight: Self.maximumInFlight) { pair in
            guard let image = await Self.capture(pair.1, maxDimension: maxDimension) else { return }
            await self?.store(image, for: pair.0.number)
            continuation.yield((pair.0, image))
        }
        continuation.finish()
    }
    return stream
}

/// Four at a time (M25). See `PreviewBatch`.
private static let maximumInFlight = 4

private static func capture(_ window: SCWindow, maxDimension: CGFloat) async -> SendableImage? {
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let configuration = SCStreamConfiguration()
    let scale = min(1, maxDimension / max(CGFloat(window.frame.width), CGFloat(window.frame.height), 1))
    configuration.width = max(1, Int(CGFloat(window.frame.width) * scale))
    configuration.height = max(1, Int(CGFloat(window.frame.height) * scale))
    configuration.showsCursor = false
    do {
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return SendableImage(image)
    } catch {
        Log.windows.notice("Preview unavailable: \(String(describing: error), privacy: .public)")
        return nil
    }
}
```

Raise the cache ceiling in the same file — a grid holds more windows than a flyout ever did:

```swift
private static let maximumEntries = 64
```

`store(_:for:)` is already `private` on the actor; if the compiler objects to calling it from the detached `Task`, make it `func store(...)` (actor-internal, still isolated) rather than reaching for `nonisolated`.

- [ ] **Step 6: Build and run the whole suite**

Run: `swift build && swift test`
Expected: build clean with zero warnings; all tests pass. Any other type conforming to `WindowPreviewing` in the test targets needs the new method — give it one that yields nothing and finishes.

- [ ] **Step 7: Commit**

```bash
git add Sources/NexusCore/Windows/WindowPreviewService.swift Tests/NexusCoreTests/WindowPreviewBatchTests.swift
git commit -m "feat: thumbnails for a whole grid, four at a time

M25. One SCShareableContent fetch for the batch instead of one per
window, cached entries answered before the fetch happens at all, and
each capture delivered as it lands so the grid fills in rather than
appearing at once."
```

---

### Task 4: `SwitcherViewModel` — data, filter, sort, grouping

**Files:**
- Create: `Sources/NexusUI/Switcher/SwitcherViewModel.swift`
- Create: `Sources/NexusUI/Switcher/SwitcherSection.swift`
- Test: `Tests/NexusUITests/SwitcherViewModelTests.swift` (create)

**Interfaces:**
- Consumes: `WindowServing` (with `close` from Task 2), `WindowPreviewing` (with `previews` from Task 3), `PermissionChecking`, `EventBus`, `ConfigurationController`, `Frecency`, `StringMatching`.
- Produces:
  - `SwitcherSection` — `struct SwitcherSection: Identifiable, Equatable { let id: String; let title: String; let windows: [NexusWindow] }`
  - `SwitcherViewModel` with: `sections: [SwitcherSection]`, `query: String`, `grouping`, `sort`, `isReversed`, `selection: Set<String>`, `focused: String?`, `previews: [CGWindowID: NSImage]`, `showsAccessibilityGate: Bool`, `showsPreviewsOffer: Bool`, and the methods `prepareForDisplay()`, `reload() async`, `activate(_:)`, `close(_:)`, `toggleSelection(_:)`, `addStack()`, `moveFocus(_:columns:)`, `activateFocused()`, `clearQueryOrClose()`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/NexusUITests/SwitcherViewModelTests.swift`:

```swift
import CoreGraphics
import Foundation
import NexusCore
import Testing

@testable import NexusUI

@Suite("Switcher view model")
@MainActor
struct SwitcherViewModelTests {
    func window(_ bundle: String, _ name: String, _ title: String, number: CGWindowID) -> NexusWindow {
        NexusWindow(
            identity: WindowIdentity(owner: ApplicationIdentity(bundleIdentifier: bundle), number: number),
            title: title,
            applicationName: name
        )
    }

    func model(_ windows: [NexusWindow]) async -> SwitcherViewModel {
        let service = FakeWindowService()
        for window in windows {
            await service.setWindows(
                windows.filter { $0.identity.owner == window.identity.owner },
                for: window.identity.owner.bundleIdentifier
            )
        }
        let model = SwitcherViewModel(
            service: service,
            previewService: FakeWindowPreviewService(),
            permissions: FakePermissionService(granted: [.accessibility]),
            events: EventBus(),
            configuration: ConfigurationController(store: ConfigurationStore(defaults: makeDefaults()))
        )
        await model.reload()
        return model
    }

    @Test("Every window is a card, one per window and not one per application")
    func cardPerWindow() async {
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Google", number: 1),
            window("com.apple.Safari", "Safari", "Nexus", number: 2),
            window("com.apple.finder", "Finder", "Macintosh HD", number: 3),
        ])
        #expect(model.sections.count == 1)
        #expect(model.sections[0].windows.count == 3)
    }

    @Test("The filter matches an application name and a window title")
    func filter() async {
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Google", number: 1),
            window("com.apple.finder", "Finder", "Downloads", number: 2),
        ])

        model.query = "saf"
        #expect(model.sections.flatMap(\.windows).map(\.title) == ["Google"])

        model.query = "down"
        #expect(model.sections.flatMap(\.windows).map(\.title) == ["Downloads"])

        model.query = "zzz"
        #expect(model.sections.flatMap(\.windows).isEmpty)

        model.query = ""
        #expect(model.sections.flatMap(\.windows).count == 2)
    }

    @Test("Sorting by title, and reversed is the exact inverse")
    func sortByTitle() async {
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Beta", number: 1),
            window("com.apple.finder", "Finder", "Alpha", number: 2),
        ])
        model.sort = .title
        #expect(model.sections.flatMap(\.windows).map(\.title) == ["Alpha", "Beta"])

        model.isReversed = true
        #expect(model.sections.flatMap(\.windows).map(\.title) == ["Beta", "Alpha"])
    }

    @Test("Recency follows activation, most recent first")
    func sortByRecency() async {
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Google", number: 1),
            window("com.apple.finder", "Finder", "Downloads", number: 2),
        ])
        model.sort = .recent
        model.noteActivation(ApplicationIdentity(bundleIdentifier: "com.apple.finder"))
        #expect(model.sections.flatMap(\.windows).map(\.applicationName) == ["Finder", "Safari"])

        model.noteActivation(ApplicationIdentity(bundleIdentifier: "com.apple.Safari"))
        #expect(model.sections.flatMap(\.windows).map(\.applicationName) == ["Safari", "Finder"])
    }

    @Test("Grouping by application makes one section per application, named for it")
    func groupByApplication() async {
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Google", number: 1),
            window("com.apple.Safari", "Safari", "Nexus", number: 2),
            window("com.apple.finder", "Finder", "Downloads", number: 3),
        ])
        model.sort = .application
        model.grouping = .application
        #expect(model.sections.map(\.title) == ["Finder", "Safari"])
        #expect(model.sections.map { $0.windows.count } == [1, 2])
    }

    @Test("Add Stack reduces a window selection to distinct applications")
    func addStack() async {
        let model = await self.model([
            window("com.apple.Safari", "Safari", "Google", number: 1),
            window("com.apple.Safari", "Safari", "Nexus", number: 2),
            window("com.apple.finder", "Finder", "Downloads", number: 3),
        ])
        model.toggleSelection("com.apple.Safari#1")
        model.toggleSelection("com.apple.Safari#2")
        model.toggleSelection("com.apple.finder#3")

        #expect(model.canAddStack)
        let group = model.stackFromSelection()
        #expect(group?.applications.sorted() == ["com.apple.Safari", "com.apple.finder"])
    }

    @Test("Add Stack is unavailable with nothing selected")
    func addStackNeedsSelection() async {
        let model = await self.model([window("com.apple.Safari", "Safari", "Google", number: 1)])
        #expect(model.canAddStack == false)
        #expect(model.stackFromSelection() == nil)
    }

    @Test("Escape clears a filter before it closes the panel")
    func escapeIsTwoSteps() async {
        let model = await self.model([window("com.apple.Safari", "Safari", "Google", number: 1)])
        var closed = false
        model.onClose = { closed = true }

        model.query = "saf"
        model.clearQueryOrClose()
        #expect(model.query.isEmpty)
        #expect(closed == false)

        model.clearQueryOrClose()
        #expect(closed)
    }

    @Test("Arrows move the focus and wrap at the ends of a row")
    func focusMoves() async {
        let model = await self.model([
            window("a.one", "One", "1", number: 1),
            window("b.two", "Two", "2", number: 2),
            window("c.three", "Three", "3", number: 3),
            window("d.four", "Four", "4", number: 4),
        ])
        // `.recent` with nothing activated yet leaves the list in enumeration order, which is
        // what makes the expected positions below readable.
        model.sort = .recent
        model.focusFirst()
        #expect(model.focused == "a.one#1")

        model.moveFocus(.right, columns: 2)
        #expect(model.focused == "b.two#2")

        // Wraps to the start of the same row rather than falling into the next one.
        model.moveFocus(.right, columns: 2)
        #expect(model.focused == "a.one#1")

        model.moveFocus(.down, columns: 2)
        #expect(model.focused == "c.three#3")
    }

    @Test("Closing a card asks the service and does not remove it")
    func closeAsksTheService() async {
        let service = FakeWindowService()
        let target = window("com.apple.Safari", "Safari", "Google", number: 1)
        await service.setWindows([target], for: "com.apple.Safari")
        let model = SwitcherViewModel(
            service: service,
            previewService: FakeWindowPreviewService(),
            permissions: FakePermissionService(granted: [.accessibility]),
            events: EventBus(),
            configuration: ConfigurationController(store: ConfigurationStore(defaults: makeDefaults()))
        )
        await model.reload()

        await model.close(target)
        #expect(await service.closed == [target.identity])
        #expect(model.sections.flatMap(\.windows).count == 1)
    }

    @Test("Accessibility denied shows the gate and no cards")
    func accessibilityGate() async {
        let model = SwitcherViewModel(
            service: FakeWindowService(),
            previewService: FakeWindowPreviewService(),
            permissions: FakePermissionService(granted: []),
            events: EventBus(),
            configuration: ConfigurationController(store: ConfigurationStore(defaults: makeDefaults()))
        )
        await model.reload()
        #expect(model.showsAccessibilityGate)
        #expect(model.sections.isEmpty)
    }

    @Test("Screen Recording denied offers it once, and never again once dismissed")
    func previewsOffer() async {
        let model = await self.model([window("com.apple.Safari", "Safari", "Google", number: 1)])
        #expect(model.showsPreviewsOffer)
        model.dismissPreviewsOffer()
        #expect(model.showsPreviewsOffer == false)
    }
}
```

`FakePermissionService`, `makeDefaults()` and `FakeWindowService` already exist in the test targets — `grep -rn "struct FakePermissionService\|func makeDefaults\|actor FakeWindowService" Tests` and reuse them rather than writing new ones. `FakeWindowPreviewService` is likely to be missing; if so, add it beside `FakeWindowService`:

```swift
actor FakeWindowPreviewService: WindowPreviewing {
    func preview(for window: WindowIdentity, maxDimension: CGFloat) async -> SendableImage? { nil }
    func invalidate(_ window: WindowIdentity) async {}
    func previews(
        for windows: [WindowIdentity],
        maxDimension: CGFloat
    ) async -> AsyncStream<(WindowIdentity, SendableImage)> {
        AsyncStream { $0.finish() }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "Switcher view model"`
Expected: FAIL — `cannot find 'SwitcherViewModel' in scope`.

- [ ] **Step 3: Write `SwitcherSection`**

Create `Sources/NexusUI/Switcher/SwitcherSection.swift`:

```swift
import Foundation
import NexusCore

/// One block of the grid. Flat grouping produces exactly one of these with an empty title, which
/// is what keeps the view free of a special case for "not grouped" (M25).
public struct SwitcherSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let windows: [NexusWindow]

    public init(id: String, title: String, windows: [NexusWindow]) {
        self.id = id
        self.title = title
        self.windows = windows
    }
}
```

- [ ] **Step 4: Write the view model**

Create `Sources/NexusUI/Switcher/SwitcherViewModel.swift`. Follow `WindowFlyoutViewModel` exactly for the observation, event-subscription and preview-request shape; this is the same kind of object with a bigger list.

```swift
import AppKit
import CoreGraphics
import NexusCore
import SwiftUI

@MainActor
@Observable
public final class SwitcherViewModel {
    public enum Direction: Sendable { case left, right, up, down }

    public private(set) var windows: [NexusWindow] = []
    public private(set) var previews: [CGWindowID: NSImage] = [:]
    public private(set) var accessibility: PermissionStatus = .denied
    public private(set) var previewsOfferDismissed = false
    public private(set) var selection: Set<String> = []
    public private(set) var focused: String?

    public var query = "" { didSet { rebuild() } }
    public var grouping: WindowSwitcherGrouping { didSet { persist(); rebuild() } }
    public var sort: WindowSwitcherSort { didSet { persist(); rebuild() } }
    public var isReversed: Bool { didSet { persist(); rebuild() } }
    public private(set) var sections: [SwitcherSection] = []

    @ObservationIgnored private let service: any WindowServing
    @ObservationIgnored private let previewService: any WindowPreviewing
    @ObservationIgnored private let permissions: any PermissionChecking
    @ObservationIgnored private let events: EventBus
    @ObservationIgnored private let configuration: ConfigurationController
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    /// Bundle identifiers, most recently activated first. Seeded from the frecency store the
    /// palette already keeps, so the very first open is not in arbitrary order.
    @ObservationIgnored private var activationOrder: [String] = []
    /// Which screen a window is on, as a name, so the view model never touches `NSScreen` in a
    /// test. Replaced in tests; the default asks the real screens.
    @ObservationIgnored public var displayName: (CGRect) -> String = SwitcherViewModel.screenName

    @ObservationIgnored public var onClose: (() -> Void)?

    public init(
        service: any WindowServing,
        previewService: any WindowPreviewing,
        permissions: any PermissionChecking,
        events: EventBus,
        configuration: ConfigurationController
    ) {
        self.service = service
        self.previewService = previewService
        self.permissions = permissions
        self.events = events
        self.configuration = configuration
        let behavior = configuration.configuration.behavior
        grouping = behavior.windowSwitcherGrouping
        sort = behavior.windowSwitcherSort
        isReversed = behavior.windowSwitcherSortReversed
        accessibility = permissions.status(of: .accessibility)
        activationOrder = Frecency(entries: configuration.configuration.frecency)
            .recents(limit: 32)
            .compactMap { $0.hasPrefix("app:") ? String($0.dropFirst(4)) : nil }
    }

    // MARK: - Lifecycle

    public func start() {
        let stream = events.events()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .applicationActivated(let identity):
                    self.noteActivation(identity)
                case .windowsChanged, .applicationTerminated, .applicationLaunched:
                    await self.reload()
                case .permissionChanged(.accessibility, let status):
                    self.accessibility = status
                    await self.reload()
                default:
                    continue
                }
            }
        }
    }

    public func stop() {
        eventTask?.cancel()
        eventTask = nil
        previewTask?.cancel()
        previewTask = nil
    }

    /// Called by the panel just before it goes on screen: the grid shows the cached snapshot at
    /// once and the fresh enumeration replaces it a moment later. An empty grid for 200 ms is
    /// worse than a stale one (spec §3).
    public func prepareForDisplay() {
        query = ""
        selection = []
        accessibility = permissions.status(of: .accessibility)
        rebuild()
        Task { await reload() }
    }

    public func reload() async {
        accessibility = permissions.status(of: .accessibility)
        guard accessibility == .granted else {
            windows = []
            rebuild()
            return
        }
        windows = (try? await service.allWindows()) ?? []
        rebuild()
        requestPreviews()
    }

    // MARK: - Gates

    public var showsAccessibilityGate: Bool { accessibility != .granted }

    public var showsPreviewsOffer: Bool {
        accessibility == .granted
            && configuration.configuration.behavior.windowSwitcherThumbnails
            && !previewsOfferDismissed
            && permissions.status(of: .screenRecording) != .granted
            && !windows.isEmpty
    }

    public func dismissPreviewsOffer() { previewsOfferDismissed = true }

    public func requestAccessibility() { permissions.requestOrOpenSettings(.accessibility) }

    public func requestScreenRecording() { permissions.requestOrOpenSettings(.screenRecording) }

    // MARK: - Recency

    public func noteActivation(_ identity: ApplicationIdentity) {
        activationOrder.removeAll { $0 == identity.bundleIdentifier }
        activationOrder.insert(identity.bundleIdentifier, at: 0)
        rebuild()
    }

    // MARK: - Building the grid

    private func rebuild() {
        let matched = windows.filter { matches($0) }
        let ordered = ordered(matched)
        switch grouping {
        case .flat:
            sections = ordered.isEmpty ? [] : [SwitcherSection(id: "all", title: "", windows: ordered)]
        case .application:
            sections = grouped(ordered, by: { $0.identity.owner.bundleIdentifier }, title: { $0.applicationName })
        case .display:
            sections = grouped(ordered, by: { displayName($0.frame) }, title: { displayName($0.frame) })
        }
        if let focused, sections.flatMap(\.windows).contains(where: { $0.id == focused }) == false {
            self.focused = nil
        }
    }

    private func matches(_ window: NexusWindow) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        // Every word has to land somewhere, so `saf goo` finds Safari's Google window while
        // `saf zzz` finds nothing.
        return StringMatching.words(in: query).allSatisfy { word in
            StringMatching.match(query: word, candidate: window.applicationName) != nil
                || StringMatching.match(query: word, candidate: window.title) != nil
        }
    }

    private func ordered(_ windows: [NexusWindow]) -> [NexusWindow] {
        let sorted: [NexusWindow] = switch sort {
        case .title:
            windows.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .application:
            windows.sorted {
                let left = $0.applicationName.localizedStandardCompare($1.applicationName)
                return left == .orderedSame ? $0.identity.number < $1.identity.number : left == .orderedAscending
            }
        case .recent:
            // Within one application, AX order is front-to-back and is left alone.
            windows.enumerated().sorted { left, right in
                let a = rank(left.element)
                let b = rank(right.element)
                return a == b ? left.offset < right.offset : a < b
            }.map(\.element)
        }
        return isReversed ? sorted.reversed() : sorted
    }

    private func rank(_ window: NexusWindow) -> Int {
        activationOrder.firstIndex(of: window.identity.owner.bundleIdentifier) ?? Int.max
    }

    private func grouped(
        _ windows: [NexusWindow],
        by key: (NexusWindow) -> String,
        title: (NexusWindow) -> String
    ) -> [SwitcherSection] {
        var order: [String] = []
        var byKey: [String: [NexusWindow]] = [:]
        var titles: [String: String] = [:]
        for window in windows {
            let id = key(window)
            if byKey[id] == nil {
                order.append(id)
                titles[id] = title(window)
            }
            byKey[id, default: []].append(window)
        }
        return order.map { SwitcherSection(id: $0, title: titles[$0] ?? $0, windows: byKey[$0] ?? []) }
    }

    private static func screenName(_ frame: CGRect) -> String {
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
            ?? NSScreen.screens.first { $0.frame.intersects(frame) }
        return screen?.localizedName ?? String(localized: "Other display")
    }

    // MARK: - Actions

    public func activate(_ window: NexusWindow) {
        Task { [service] in try? await service.activate(window.identity) }
        onClose?()
    }

    public func close(_ window: NexusWindow) async {
        // The card stays until `windowsChanged` says otherwise: a document with unsaved work
        // puts up a sheet and the window is still there (spec §6).
        try? await service.close(window.identity)
    }

    public func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    public var canAddStack: Bool { !selection.isEmpty }

    /// The selection is windows; a stack is applications. Window identity does not survive a
    /// relaunch, so a stack of windows would empty itself overnight (spec §7).
    public func stackFromSelection() -> ApplicationGroup? {
        let bundles = windows
            .filter { selection.contains($0.id) }
            .map(\.identity.owner.bundleIdentifier)
        var distinct: [String] = []
        for bundle in bundles where !distinct.contains(bundle) { distinct.append(bundle) }
        guard !distinct.isEmpty else { return nil }
        return ApplicationGroup(name: String(localized: "Stack"), applications: distinct)
    }

    public func addStack() {
        guard let group = stackFromSelection() else { return }
        configuration.update { $0.dock.entries.append(.group(group)) }
        selection = []
    }

    // MARK: - Keyboard

    public func focusFirst() {
        focused = sections.first?.windows.first?.id
    }

    public func clearQueryOrClose() {
        if query.isEmpty { onClose?() } else { query = "" }
    }

    public func activateFocused() {
        guard let focused, let window = sections.flatMap(\.windows).first(where: { $0.id == focused })
        else { return }
        activate(window)
    }

    public func closeFocused() async {
        guard let focused, let window = sections.flatMap(\.windows).first(where: { $0.id == focused })
        else { return }
        await close(window)
    }

    /// Moves within one row for left and right — wrapping at its ends rather than spilling into
    /// the next row, which is what makes a grid feel like a grid — and by a whole row for up and
    /// down.
    public func moveFocus(_ direction: Direction, columns: Int) {
        let all = sections.flatMap(\.windows)
        guard !all.isEmpty else { return }
        let columns = max(1, columns)
        guard let focused, let index = all.firstIndex(where: { $0.id == focused }) else {
            self.focused = all.first?.id
            return
        }
        let row = index / columns
        let column = index % columns
        let rowStart = row * columns
        let rowCount = min(columns, all.count - rowStart)
        let next: Int = switch direction {
        case .left: rowStart + (column - 1 + rowCount) % rowCount
        case .right: rowStart + (column + 1) % rowCount
        case .up: max(0, index - columns)
        case .down: min(all.count - 1, index + columns)
        }
        self.focused = all[next].id
    }

    // MARK: - Previews

    private func requestPreviews() {
        guard configuration.configuration.behavior.windowSwitcherThumbnails,
              permissions.status(of: .screenRecording) == .granted
        else { return }
        let identities = windows.map(\.identity)
        previewTask?.cancel()
        previewTask = Task { [previewService] in
            for await (identity, image) in await previewService.previews(for: identities, maxDimension: 480) {
                guard !Task.isCancelled else { return }
                previews[identity.number] = NSImage(
                    cgImage: image.image,
                    size: NSSize(width: image.image.width, height: image.image.height)
                )
            }
        }
    }

    private func persist() {
        configuration.update {
            $0.behavior.windowSwitcherGrouping = grouping
            $0.behavior.windowSwitcherSort = sort
            $0.behavior.windowSwitcherSortReversed = isReversed
        }
    }
}
```

Check three names against the real code before compiling: `configuration.configuration.dock.entries` (the dock's entry array — `grep -n "entries" Sources/NexusCore/Configuration/NexusConfiguration.swift`), `Frecency.recents`'s key prefix (`grep -n "app:" Sources/NexusCore/Search`), and `EventBus.events()`. Use whatever those actually are.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter "Switcher view model"`
Expected: PASS. Where a test depends on a name that differs in the real code, fix the test to the real name — never the other way round.

- [ ] **Step 6: Run the whole suite**

Run: `swift test`
Expected: PASS, no warnings.

- [ ] **Step 7: Commit**

```bash
git add Sources/NexusUI/Switcher Tests/NexusUITests/SwitcherViewModelTests.swift
git commit -m "feat: the switcher's model — every window, filtered, sorted, grouped

M25. One card per window rather than per application, which is the whole
reason to have it: ⌘Tab already reaches applications and cannot reach a
second window. Recency comes from applicationActivated and is seeded from
the frecency store the palette keeps."
```

---

### Task 5: The grid view

**Files:**
- Create: `Sources/NexusUI/Switcher/SwitcherView.swift`
- Create: `Sources/NexusUI/Switcher/SwitcherCard.swift`
- Create: `Sources/NexusUI/Switcher/SwitcherLayout.swift`
- Test: `Tests/NexusUITests/SwitcherLayoutTests.swift` (create)

**Interfaces:**
- Consumes: `SwitcherViewModel`, `SwitcherSection`, `IconCache`, `PermissionRequestView`, `DesignMetrics`.
- Produces: `SwitcherView(model:)`, `SwitcherCard(window:preview:isSelected:isFocused:onActivate:onClose:onToggleSelection:)`, `SwitcherLayout.columns(forWidth:cardWidth:spacing:)`, `SwitcherLayout.cardWidth`, `SwitcherLayout.cardHeight`.

- [ ] **Step 1: Write the failing test**

Create `Tests/NexusUITests/SwitcherLayoutTests.swift`:

```swift
import CoreGraphics
import Testing

@testable import NexusUI

@Suite("Switcher layout")
struct SwitcherLayoutTests {
    @Test("Columns fill the width and never drop below one")
    func columns() {
        #expect(SwitcherLayout.columns(forWidth: 1600, cardWidth: 320, spacing: 20) == 4)
        #expect(SwitcherLayout.columns(forWidth: 700, cardWidth: 320, spacing: 20) == 2)
        #expect(SwitcherLayout.columns(forWidth: 100, cardWidth: 320, spacing: 20) == 1)
        #expect(SwitcherLayout.columns(forWidth: 0, cardWidth: 320, spacing: 20) == 1)
    }

    @Test("A card is wider than it is tall, in the proportions of a screen")
    func cardShape() {
        #expect(SwitcherLayout.cardWidth > SwitcherLayout.cardHeight)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter "Switcher layout"`
Expected: FAIL — `cannot find 'SwitcherLayout' in scope`.

- [ ] **Step 3: Write the layout constants**

Create `Sources/NexusUI/Switcher/SwitcherLayout.swift`:

```swift
import CoreGraphics
import Foundation

/// The grid's measurements, kept out of the view so the column count can be tested without one.
public enum SwitcherLayout {
    /// Wide enough for a legible thumbnail of a 16:10 screen, narrow enough that four fit across
    /// a 1440-point display.
    public static let cardWidth: CGFloat = 320
    public static let cardHeight: CGFloat = 220
    public static let spacing: CGFloat = 20
    public static let toolbarHeight: CGFloat = 52

    public static func columns(forWidth width: CGFloat, cardWidth: CGFloat, spacing: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        return max(1, Int((width + spacing) / (cardWidth + spacing)))
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter "Switcher layout"`
Expected: PASS.

- [ ] **Step 5: Write the card**

Create `Sources/NexusUI/Switcher/SwitcherCard.swift`. Read `Sources/NexusUI/Sidebar/WindowFlyoutView.swift` first and match how it draws a thumbnail, an icon and a title — this is the same card at a larger size.

```swift
import AppKit
import NexusCore
import SwiftUI

struct SwitcherCard: View {
    let window: NexusWindow
    let preview: NSImage?
    let isSelected: Bool
    let isFocused: Bool
    let onActivate: () -> Void
    let onClose: () -> Void
    let onToggleSelection: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon = IconCache.shared.icon(forBundleIdentifier: window.identity.owner.bundleIdentifier) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(window.applicationName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(window.isMinimized ? String(localized: "Minimized") : window.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                // The close button appears on hover only: a permanent one on every card turns a
                // grid of windows into a grid of buttons.
                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Close window"))
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.25))
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let icon = IconCache.shared.icon(forBundleIdentifier: window.identity.owner.bundleIdentifier) {
                    // No capture: the application's own icon, large. A grey rectangle says
                    // nothing about which window this is.
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .opacity(window.isMinimized ? 0.5 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(10)
        .frame(width: SwitcherLayout.cardWidth, height: SwitcherLayout.cardHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColour, lineWidth: isSelected || isFocused ? 2 : 0)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) { onToggleSelection() } else { onActivate() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.applicationName) — \(window.title)")
        .accessibilityAddTraits(.isButton)
    }

    private var borderColour: Color {
        if isSelected { return .accentColor }
        return isFocused ? .white.opacity(0.6) : .clear
    }
}
```

`IconCache`'s real accessor may not be `shared.icon(forBundleIdentifier:)` — `grep -n "public" Sources/NexusCore/Utilities/IconCache.swift` and use what is there, exactly as `WindowFlyoutView` calls it.

- [ ] **Step 6: Write the grid**

Create `Sources/NexusUI/Switcher/SwitcherView.swift`:

```swift
import AppKit
import NexusCore
import SwiftUI

public struct SwitcherView: View {
    @Bindable var model: SwitcherViewModel

    public init(model: SwitcherViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.3)
            if model.showsAccessibilityGate {
                PermissionRequestView(permission: .accessibility, permissions: model.permissionsForView)
                    .frame(maxHeight: .infinity)
            } else {
                if model.showsPreviewsOffer { previewsOffer }
                grid
            }
        }
        .background(.black.opacity(0.35))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $model.grouping) {
                Image(systemName: "square.grid.2x2").tag(WindowSwitcherGrouping.flat)
                Image(systemName: "square.stack").tag(WindowSwitcherGrouping.application)
                Image(systemName: "display.2").tag(WindowSwitcherGrouping.display)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .accessibilityLabel(String(localized: "Grouping"))

            Button(String(localized: "Add Stack"), systemImage: "plus.rectangle.on.folder") {
                model.addStack()
            }
            .disabled(!model.canAddStack)

            Spacer()

            TextField(String(localized: "Filter…"), text: $model.query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            Spacer()

            Picker("", selection: $model.sort) {
                Text("Recent Apps").tag(WindowSwitcherSort.recent)
                Text("Application").tag(WindowSwitcherSort.application)
                Text("Window Title").tag(WindowSwitcherSort.title)
            }
            .frame(width: 160)
            .accessibilityLabel(String(localized: "Sort"))

            Button {
                model.isReversed.toggle()
            } label: {
                Image(systemName: model.isReversed ? "arrow.up" : "arrow.down")
            }
            .accessibilityLabel(String(localized: "Reverse the order"))
        }
        .padding(.horizontal, 16)
        .frame(height: SwitcherLayout.toolbarHeight)
    }

    private var previewsOffer: some View {
        HStack(spacing: 12) {
            Text("Turn on Screen Recording to see what is in each window.")
                .font(.callout)
            Button(String(localized: "Open Settings…")) { model.requestScreenRecording() }
            Button(String(localized: "Not now")) { model.dismissPreviewsOffer() }
                .buttonStyle(.plain)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    private var grid: some View {
        GeometryReader { proxy in
            let columns = SwitcherLayout.columns(
                forWidth: proxy.size.width - 32,
                cardWidth: SwitcherLayout.cardWidth,
                spacing: SwitcherLayout.spacing
            )
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(model.sections) { section in
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.headline)
                                .padding(.horizontal, 16)
                        }
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.fixed(SwitcherLayout.cardWidth), spacing: SwitcherLayout.spacing),
                                count: columns
                            ),
                            spacing: SwitcherLayout.spacing
                        ) {
                            ForEach(section.windows) { window in
                                SwitcherCard(
                                    window: window,
                                    preview: model.previews[window.identity.number],
                                    isSelected: model.selection.contains(window.id),
                                    isFocused: model.focused == window.id,
                                    onActivate: { model.activate(window) },
                                    onClose: { Task { await model.close(window) } },
                                    onToggleSelection: { model.toggleSelection(window.id) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: proxy.size.width) { _, _ in model.columns = columns }
            .onAppear { model.columns = columns }
        }
    }
}
```

This needs two small additions to the view model from Task 4 — add them now:

```swift
/// How many cards are across, published by the view so the arrow keys move by a real row.
public var columns = 1
/// The permission service, for the gate view, which takes one.
public var permissionsForView: any PermissionChecking { permissions }
```

(`permissions` must lose `private` for that, or expose it as above.)

- [ ] **Step 7: Build and run the suite**

Run: `swift build && swift test`
Expected: build clean, all tests pass. `PermissionRequestView`'s initialiser has more parameters than shown here — read `Sources/NexusUI/Permissions/PermissionRequestView.swift:20` and pass what it actually wants, copying the call site in `WindowFlyoutView`.

- [ ] **Step 8: Commit**

```bash
git add Sources/NexusUI/Switcher Tests/NexusUITests/SwitcherLayoutTests.swift
git commit -m "feat: the switcher's grid, its toolbar and its cards

M25. A card is an icon, an application, a title and a thumbnail, with a
close button that only appears under the pointer. Without a capture the
card shows the application's icon large rather than a grey rectangle."
```

---

### Task 6: The panel

**Files:**
- Create: `Sources/NexusUI/Panels/SwitcherPanelController.swift`
- Test: `Tests/NexusUITests/SwitcherPanelTests.swift` (create)

**Interfaces:**
- Consumes: `SwitcherViewModel`, `SwitcherView`, `DisplayService`, `FirstMouseHostingView` (from `Sources/NexusUI/Support/HostingViews.swift`).
- Produces: `SwitcherPanel`, `SwitcherPanelController(model:)` with `start()`, `stop()`, `toggle()`, `show()`, `hide(restoreFocus:)`, `isVisible`, and `SwitcherPanelController.frame(for screen: CGRect) -> CGRect`.

- [ ] **Step 1: Write the failing test**

Create `Tests/NexusUITests/SwitcherPanelTests.swift`:

```swift
import CoreGraphics
import Testing

@testable import NexusUI

@Suite("Switcher panel")
struct SwitcherPanelTests {
    @Test("The panel fills the visible area of its screen")
    func fillsTheScreen() {
        let visible = CGRect(x: 0, y: 0, width: 2560, height: 1410)
        #expect(SwitcherPanelController.frame(for: visible) == visible)
    }

    @Test("A screen with an origin away from zero is respected")
    func secondDisplay() {
        let visible = CGRect(x: 2560, y: 0, width: 2560, height: 1440)
        #expect(SwitcherPanelController.frame(for: visible) == visible)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter "Switcher panel"`
Expected: FAIL — `cannot find 'SwitcherPanelController' in scope`.

- [ ] **Step 3: Write the panel controller**

Create `Sources/NexusUI/Panels/SwitcherPanelController.swift`. Read `SearchPanelController.swift` completely first: the activation strategy, the dismissal monitors and the key-window verification are copied from it deliberately, and a partial copy is what produces a panel nobody can type into.

```swift
import AppKit
import NexusCore
import SwiftUI

/// Like the palette, the switcher must take the keyboard and give it back.
public final class SwitcherPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = false
        animationBehavior = .none
        hasShadow = false
        isReleasedWhenClosed = false
        canHide = false
        title = "Nexus Window Switcher"
        self.contentView = contentView
    }
}

@MainActor
public final class SwitcherPanelController {
    private let model: SwitcherViewModel
    private var panel: SwitcherPanel?
    private var previousApplication: NSRunningApplication?
    private var keyMonitor: Any?
    private var resignObserver: (any NSObjectProtocol)?

    public private(set) var isVisible = false

    public init(model: SwitcherViewModel) {
        self.model = model
    }

    public func start() {
        let hosting = FirstMouseHostingView(rootView: SwitcherView(model: model))
        panel = SwitcherPanel(contentView: hosting)
        model.onClose = { [weak self] in self?.hide(restoreFocus: true) }
        model.start()
    }

    public func stop() {
        model.stop()
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    public func toggle() {
        if isVisible { hide(restoreFocus: true) } else { show() }
    }

    public func show() {
        guard let panel else { return }
        previousApplication = NSWorkspace.shared.frontmostApplication
        model.prepareForDisplay()

        let screen = DisplayService.screenContainingMouse() ?? NSScreen.main
        if let screen { panel.setFrame(Self.frame(for: screen.visibleFrame), display: true) }

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        installMonitors(panel)
        isVisible = true
        model.focusFirst()
    }

    /// `restoreFocus` is false when a card was clicked: that window is the destination, and it has
    /// already been raised.
    public func hide(restoreFocus: Bool) {
        guard let panel, isVisible else { return }
        removeMonitors()
        panel.orderOut(nil)
        isVisible = false
        if restoreFocus { previousApplication?.activate() }
        previousApplication = nil
    }

    /// The whole visible area. Not `screen.frame`: the menu bar stays where it is, because a
    /// switcher that hides it looks like a crash for the half-second before it is read.
    public static func frame(for visibleFrame: CGRect) -> CGRect { visibleFrame }

    // MARK: - Keyboard and dismissal

    /// The filter field holds first responder the whole time, so the arrows and `Tab` are taken
    /// before it sees them — the same local monitor the palette uses for its digit chords.
    private func installMonitors(_ panel: SwitcherPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            switch Int(event.keyCode) {
            case 123: self.model.moveFocus(.left, columns: self.model.columns); return nil
            case 124: self.model.moveFocus(.right, columns: self.model.columns); return nil
            case 125: self.model.moveFocus(.down, columns: self.model.columns); return nil
            case 126: self.model.moveFocus(.up, columns: self.model.columns); return nil
            case 36, 76: self.model.activateFocused(); return nil                     // Return, Enter
            case 53: self.model.clearQueryOrClose(); return nil                       // Escape
            case 13 where event.modifierFlags.contains(.command):                     // ⌘W
                Task { await self.model.closeFocused() }
                return nil
            default:
                return event
            }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                // Command-Tab, a click elsewhere, another hotkey: the panel has lost the keyboard
                // and has nothing left to do.
                self.hide(restoreFocus: false)
            }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }
}
```

A click on the panel's background must close it too. Add to `SwitcherView`'s outermost `background` modifier:

```swift
.contentShape(Rectangle())
.onTapGesture { model.onClose?() }
```

placed on the `VStack`'s background layer, not on the whole stack, or it swallows the cards' own taps. If that proves fiddly in the view, put a `Color.black.opacity(0.35)` in a `ZStack` behind everything and attach the gesture to that instead.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "Switcher panel"`
Expected: PASS.

- [ ] **Step 5: Run the whole suite and build**

Run: `swift build && swift test`
Expected: clean build, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/NexusUI/Panels/SwitcherPanelController.swift Sources/NexusUI/Switcher/SwitcherView.swift Tests/NexusUITests/SwitcherPanelTests.swift
git commit -m "feat: the switcher's panel, on the display under the pointer

M25. Borderless, over every Space and over full screen, filling the
visible area but never the menu bar. Arrows and Return are taken by a
local monitor before the filter field sees them, which is what lets the
field keep focus and the grid still answer to the keyboard."
```

---

### Task 7: The shortcut, and wiring it up

**Files:**
- Modify: `Sources/NexusCore/System/HotKeyService.swift`
- Modify: `Sources/NexusApp/Composition.swift`
- Test: `Tests/NexusCoreTests/SystemServiceTests.swift`

**Interfaces:**
- Consumes: Task 1's `windowSwitcherShortcut`, Task 6's `SwitcherPanelController`.
- Produces: `HotKeyService.Slot.windowSwitcher`, and a `switcherPanel` on the composition root.

- [ ] **Step 1: Write the failing test**

Add to `Tests/NexusCoreTests/SystemServiceTests.swift`:

```swift
@Test("Every hotkey slot has its own Carbon identifier")
func slotsAreDistinct() {
    let identifiers = HotKeyService.Slot.allCases.map(\.rawValue)
    #expect(Set(identifiers).count == identifiers.count)
    #expect(HotKeyService.Slot.allCases.contains(.windowSwitcher))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter slotsAreDistinct`
Expected: FAIL — `type 'HotKeyService.Slot' has no member 'windowSwitcher'`.

- [ ] **Step 3: Add the slot**

In `Sources/NexusCore/System/HotKeyService.swift`:

```swift
case windowSwitcher = 3
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter slotsAreDistinct`
Expected: PASS.

- [ ] **Step 5: Wire the panel into the composition root**

In `Sources/NexusApp/Composition.swift`, beside the other panel controllers:

```swift
let switcherModel = SwitcherViewModel(
    service: windows,
    previewService: windowPreviews,
    permissions: permissions,
    events: events,
    configuration: configuration
)
lazy var switcherPanel = SwitcherPanelController(model: switcherModel)
```

Use the property names the file already has for the window service, the preview service, the permission service, the event bus and the configuration controller — `grep -n "let windows\|let permissions\|let events\|let configuration" Sources/NexusApp/Composition.swift`.

Start and stop it where the other panels are started and stopped (`grep -n "searchPanel.start()\|searchPanel.stop()"`), then extend `registerHotKey()`:

```swift
case .windowSwitcher: switcherPanel.toggle()
```

in the `switch slot` block, and after the focus-bar registration:

```swift
// The switcher's shortcut (M25). Optional in the same way the bar's is: a machine where
// something else already owns the combination simply does not get it.
if let switcher = configuration.configuration.general.windowSwitcherShortcut {
    if case .failure(let error) = hotKeys.register(switcher, for: .windowSwitcher) {
        Log.system.error("Could not register the switcher shortcut: \(String(describing: error), privacy: .public)")
    }
} else {
    hotKeys.unregister(.windowSwitcher)
}
```

- [ ] **Step 6: Build, test, and try it for real**

Run: `swift build && swift test`
Expected: clean build, all tests pass.

Then: `make stop && make run`, press `⌃⌥W`.
Expected: the grid appears on the display holding the pointer, arrow keys move the highlight, Return activates a window and the panel closes, Escape closes it, `⌃⌥W` again toggles it.

- [ ] **Step 7: Commit**

```bash
git add Sources/NexusCore/System/HotKeyService.swift Sources/NexusApp/Composition.swift Tests/NexusCoreTests/SystemServiceTests.swift
git commit -m "feat: ⌃⌥W opens the window switcher

M25. A third Carbon slot, registered the way the bar's is: optional, and
a machine where something else already owns the combination keeps
working without it."
```

---

### Task 8: The Shortcuts tab

**Files:**
- Modify: `Sources/NexusUI/Settings/SettingsView.swift`
- Test: `Tests/NexusCoreTests/SettingsPaneTests.swift` — *only if that suite covers settings panes; otherwise add the test to `Tests/NexusUITests/DesignTests.swift`, which is where view-level expectations already live.*

**Interfaces:**
- Consumes: `ShortcutRecorder`, `ConfigurationController`, Task 1's `windowSwitcherShortcut`.
- Produces: `ShortcutsPane`, and a `shortcutConflict(_:)` helper on it.

- [ ] **Step 1: Write the failing test**

Add to the chosen test file:

```swift
@Test("Two slots holding the same combination is reported")
func shortcutConflictIsFound() {
    var configuration = NexusConfiguration()
    configuration.search.shortcut = .optionSpace
    configuration.general.focusBarShortcut = .optionSpace

    #expect(ShortcutsPane.conflicts(in: configuration).contains(.optionSpace))
}

@Test("Distinct combinations conflict with nothing")
func noConflictWhenDistinct() {
    var configuration = NexusConfiguration()
    configuration.search.shortcut = .optionSpace
    configuration.general.focusBarShortcut = .focusBarDefault
    configuration.general.windowSwitcherShortcut = .windowSwitcherDefault

    #expect(ShortcutsPane.conflicts(in: configuration).isEmpty)
}
```

The test target must be able to see `ShortcutsPane`, so declare it `struct ShortcutsPane: View` (internal) in `NexusUI` and let `@testable import NexusUI` reach it.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter shortcutConflictIsFound`
Expected: FAIL — `cannot find 'ShortcutsPane' in scope`.

- [ ] **Step 3: Write the pane**

In `Sources/NexusUI/Settings/SettingsView.swift`, after `BehaviorPane`:

```swift
// MARK: - Shortcuts

/// Every global shortcut in one place. They used to live in the tab of the feature they belonged
/// to, which answered "how do I change the palette's shortcut" and never "what is bound to what"
/// (M25).
struct ShortcutsPane: View {
    @Bindable var configuration: ConfigurationController
    let validateShortcut: (NexusCore.KeyboardShortcut) -> String?

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Open search")) {
                    ShortcutRecorder(
                        shortcut: configuration.binding(\.search.shortcut),
                        validate: validateShortcut
                    )
                }
                if configuration.configuration.search.shortcut.isCommandSpace {
                    SpotlightGuideView()
                }
            }
            Section {
                Toggle(
                    String(localized: "Keyboard access to the bar"),
                    isOn: Binding(
                        get: { configuration.configuration.general.focusBarShortcut != nil },
                        set: { on in
                            configuration.update { $0.general.focusBarShortcut = on ? .focusBarDefault : nil }
                        }
                    )
                )
                if let current = configuration.configuration.general.focusBarShortcut {
                    LabeledContent(String(localized: "Focus the bar")) {
                        ShortcutRecorder(
                            shortcut: Binding(
                                get: { current },
                                set: { new in configuration.update { $0.general.focusBarShortcut = new } }
                            ),
                            validate: { _ in nil }
                        )
                    }
                }
                Text("Puts the keyboard on the bar: arrows move along it, Return opens what is focused, Escape gives the keyboard back. It also returns on its own after ten seconds of nothing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(
                    String(localized: "Window switcher"),
                    isOn: Binding(
                        get: { configuration.configuration.general.windowSwitcherShortcut != nil },
                        set: { on in
                            configuration.update {
                                $0.general.windowSwitcherShortcut = on ? .windowSwitcherDefault : nil
                            }
                        }
                    )
                )
                if let current = configuration.configuration.general.windowSwitcherShortcut {
                    LabeledContent(String(localized: "Open the switcher")) {
                        ShortcutRecorder(
                            shortcut: Binding(
                                get: { current },
                                set: { new in configuration.update { $0.general.windowSwitcherShortcut = new } }
                            ),
                            validate: { _ in nil }
                        )
                    }
                }
                Text("A grid of every open window: type to filter it, arrows to move, Return to go there. ⌘-click cards and Add Stack puts their applications in the bar as a group.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !Self.conflicts(in: configuration.configuration).isEmpty {
                Section {
                    Text("Two shortcuts are the same combination. Only the first one registered will work.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Combinations claimed by more than one slot. Carbon registers the first and refuses the
    /// rest, which is silent — so it is said here instead.
    static func conflicts(in configuration: NexusConfiguration) -> Set<NexusCore.KeyboardShortcut> {
        let all = [
            configuration.search.shortcut,
            configuration.general.focusBarShortcut,
            configuration.general.windowSwitcherShortcut,
        ].compactMap { $0 }
        var seen: Set<NexusCore.KeyboardShortcut> = []
        var repeated: Set<NexusCore.KeyboardShortcut> = []
        for shortcut in all where !seen.insert(shortcut).inserted { repeated.insert(shortcut) }
        return repeated
    }
}
```

`KeyboardShortcut` is already `Hashable` (Task 1's file shows `Codable, Sendable, Equatable, Hashable`). If it is not, add `Hashable` to it in `NexusConfiguration.swift`.

- [ ] **Step 4: Add the tab and remove the two moved rows**

In `SettingsView.body`, after `BehaviorPane`:

```swift
ShortcutsPane(configuration: configuration, validateShortcut: validateShortcut)
    .tabItem { Label(String(localized: "Shortcuts"), systemImage: "keyboard") }
```

Then **delete** the section holding `ShortcutRecorder` from `SearchPane` (the "Global shortcut" `LabeledContent` and its `SpotlightGuideView`) and the focus-bar section from `BarPane` (`SettingsView.swift:580-608`, the `Toggle`, the `LabeledContent`, and the caption). They are moved, not copied: two places to change one shortcut is the problem this tab exists to solve.

- [ ] **Step 5: Run the tests**

Run: `swift test`
Expected: PASS. `SearchPane` may now have an unused `validateShortcut` parameter — remove it from the struct and from its call site in `SettingsView.body` if the compiler warns.

- [ ] **Step 6: Check it by hand**

Run: `make stop && make run`, open Settings.
Expected: a Shortcuts tab holding all three recorders; Search and Bar no longer show one; setting two of them to the same combination shows the red conflict line.

- [ ] **Step 7: Commit**

```bash
git add Sources/NexusUI/Settings/SettingsView.swift Tests
git commit -m "feat: one tab for every shortcut

M25. The palette's lived in Search and the bar's in Bar, which answered
'how do I change this one' and never 'what is bound to what'. All three
move to a Shortcuts tab, which also says when two of them are the same
combination — something Carbon refuses silently."
```

---

### Task 9: Documentation and the verification checklist

**Files:**
- Modify: `docs/decisions.md` (or `docs/decisions/windows.md` — put the entries wherever the existing D1…D111 numbering lives; `grep -rn "D111" docs`)
- Modify: `CHANGELOG.md`
- Modify: `FEATURES.md`
- Modify: `ROADMAP.md`
- Modify: `docs/verification.md`
- Modify: `docs/design/window-switcher.md`

**Interfaces:** none — documentation only.

- [ ] **Step 1: Write the decisions**

Append, continuing the existing numbering from D111 and matching the surrounding format exactly:

- **D112 — The switcher shows one card per window, not per application.** `⌘Tab` already reaches applications and cannot reach a second window; a switcher that repeats it is a worse `⌘Tab`.
- **D113 — Bulk previews fetch `SCShareableContent` once and capture four at a time.** The fetch is the expensive part; per-window fetches made a twelve-window grid unusable. Four rather than all of them because the work is one compositor's either way.
- **D114 — The switcher asks for Screen Recording; the hover flyout still does not.** A missing thumbnail in a flyout is a garnish; a wall of identical icons in a switcher is the feature failing at its only job.
- **D115 — Add Stack stores applications, not windows.** Window identity does not survive a relaunch, so a stack of windows would empty itself overnight.
- **D116 — Escape clears the filter before it closes the panel.** What every macOS search field does, and it stops a mistyped filter from costing the whole panel.
- **D117 — Every global shortcut moved to one Shortcuts tab.** Per-feature homes answered "how do I change this one" and never "what is bound to what".

- [ ] **Step 2: Update the feature and roadmap documents**

- `FEATURES.md`: a Window Switcher entry beside the other features, in the same shape as its neighbours.
- `ROADMAP.md`: M25 marked as shipped, with the same "What shipped" summary style used for M24.
- `CHANGELOG.md`: an entry at the top in the existing format.
- `docs/design/window-switcher.md`: a **What shipped** section, in the shape the other design documents use — what was built as specified, and anything the spec did not anticipate.

- [ ] **Step 3: Add the manual checks**

In `docs/verification.md`, beside the existing manual checks:

```markdown
### Window switcher (M25)

- `⌃⌥W` opens the grid on the display holding the pointer, over a full-screen application, without
  switching Spaces.
- Every open window has a card, minimized ones included and marked.
- Typing filters by application and by window title; Escape clears the filter, Escape again closes.
- Arrows move the highlight and wrap at the ends of a row; Return activates; ⌘W closes a window.
- Clicking a card activates that window and closes the panel; clicking the background just closes.
- With Screen Recording denied: the offer appears once, dismissing it hides it for good, and the
  grid still works with icons.
- With Accessibility denied: the panel shows the gate and no cards.
- ⌘-click two cards from different applications, Add Stack, and the group appears in the bar.
- VoiceOver reads each card as "<application> — <title>", and the toolbar controls are labelled.
```

- [ ] **Step 4: Run everything one more time**

Run: `swift build && swift test`
Expected: clean build, zero warnings, every test passing. Record the final test count in the commit body.

- [ ] **Step 5: Commit**

```bash
git add docs CHANGELOG.md FEATURES.md ROADMAP.md
git commit -m "docs: the window switcher, as shipped

M25, with D112–D117 and the manual checks it needs: a grant of Screen
Recording, a denial of it, a full-screen space, and a second display."
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| §1 Shape | 5 |
| §2 Opening and closing | 6, 7 |
| §3 What is in the grid | 4 |
| §4 Filter, sort, group | 4 |
| §5 Thumbnails and the permission | 3, 4, 5 |
| §6 Card actions | 2, 4, 5 |
| §7 Add Stack | 4, 5 |
| §8 Keyboard | 4, 6 |
| §9 The Shortcuts tab | 8 |
| §10 Settings | 1 |
| Tests list | 1, 3, 4, 5, 6, 7, 8 |

**Known gaps, deliberately left:**

- The spec's "the panel is put on screen with the cached snapshot while the fresh pass completes" is implemented as `prepareForDisplay()` rebuilding from the model's existing `windows` before `reload()` replaces them. On the very first open of a session that list is empty, so the first grid appears a beat later. Acceptable, and the alternative — enumerating on a timer — is forbidden (§65).
- Sort within an application is "AX order" only for `.recent`; `.application` sorts by window number as a stand-in, which is AX order in practice because that is the order the numbers were handed out in.
