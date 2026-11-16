# Smooth Bar (Week 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the three causes of visible stutter in the bar: a script that blocks the main thread, a window that snaps while its content eases, and refresh work that lands in the middle of an animation.

**Architecture:** Nothing new is drawn. The media script moves behind a `ScriptRunning` protocol whose real implementation runs on a serial background queue with a timeout. The bar's window stops being animated: the window takes its final frame in one step and the SwiftUI content animates inside it, so the two can no longer disagree. Refresh work started by the pointer entering the bar waits until the motion has settled. A stall monitor, off unless an environment variable is set, gives a number before and after.

**Tech Stack:** Swift 6 (tools 6.0), macOS 14 floor, SwiftUI + AppKit, Swift Testing (`import Testing`, `@Test`, `#expect`), `os.Logger`.

**Spec:** `docs/reviews/2026-11-15-feature-review.html` (Improve 3) and `docs/design/2026-11-16-motion-and-menus-mockup.html` (the motion values). The diagnosis this plan acts on was made by reading the code on 2026-11-16, not by profiling; Task 1 exists so that every later task is measured.

**Branch:** `feat/smooth-bar` from `main`. Merge with `--no-ff` when Task 5 passes. Do not push; the owner pushes.

## Global Constraints

- Swift 6 strict concurrency. `make lint` must print `OK: zero warnings`.
- `swift test` passes, then passes three more times under full processor load: one `yes > /dev/null &` per core, `swift test`, then always `pkill -x yes`.
- Tests never touch the real `com.congbui.nexus` defaults domain. Use `ScratchDefaults` (`Tests/NexusCoreTests/ScratchDefaults.swift`). Never `UserDefaults(suiteName:)`.
- Tests wait with `waitUntil` (`Tests/NexusUITests/WaitUntil.swift`), never with a fixed sleep, except to show that something does not happen.
- Every animation is gated on Reduce Motion through `Design.animation(_:reduceMotion:)` or `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
- No new dependency. No private API.
- Logs carry no personal data: bundle identifiers and durations only, never window titles or file paths.
- `log` is shadowed on this machine: use `/usr/bin/log` or `make logs`.
- Sign with the "Bugler Local Dev" certificate (the Makefile finds it). Never ad-hoc.
- Commit after each task, conventional prefix (`feat:`, `fix:`, `test:`, `docs:`).

## Review Focus

1. A player that never answers (hung, or showing a modal dialog): the bar must stay responsive and the timeline must disappear, not freeze. Pinned by Task 2 test "a script that times out does not block the main actor".
2. The pointer leaving the bar halfway through the expand: the bar must turn round from where it is, and the window must end at the collapsed frame. Pinned by Task 4 test "collapse during expand ends at the collapsed frame".
3. Reduce Motion on: every frame change is immediate and the window is never left wide. Pinned by Task 4 test "reduce motion shrinks the window at once".
4. Auto-hide with a bar on every display: all bars slide and all windows end parked off screen. Pinned by Task 4 test "hide parks every bar".
5. The pointer sweeping across the bar in under 300 ms: no refresh runs at all. Pinned by Task 3 test "leaving before the settle delay cancels the refresh".

---

### Task 1: Stall monitor

A number for "stuck". A background timer pings the main queue every 8 ms; when a ping is answered late, the delay is logged.

**Files:**
- Create: `Sources/NexusCore/Utilities/StallMonitor.swift`
- Modify: `Sources/NexusApp/Composition.swift` (start it beside the other services)
- Test: `Tests/NexusCoreTests/StallMonitorTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public final class StallMonitor: Sendable {
      public static let environmentKey = "NEXUS_STALL_LOG"
      public init(threshold: Duration = .milliseconds(32), interval: Duration = .milliseconds(8),
                  report: @escaping @Sendable (Duration) -> Void)
      public func start()
      public func stop()
      public static func isRequested(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool
  }
  ```
  `report` is called off the main thread with the length of each stall at or above `threshold`. `isRequested` is true only when the variable equals `"1"`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test("A main thread blocked for 120 ms is reported once, at 100 ms or more")
@MainActor func reportsAStall() async throws {
    let stalls = Mutex<[Duration]>([])
    let monitor = StallMonitor(report: { d in stalls.withLock { $0.append(d) } })
    monitor.start(); defer { monitor.stop() }
    try await Task.sleep(for: .milliseconds(50))
    Thread.sleep(forTimeInterval: 0.12)
    try await waitUntil { stalls.withLock { !$0.isEmpty } }
    #expect(stalls.withLock { $0.first ?? .zero } >= .milliseconds(100))
}

@Test("Only the exact value 1 switches it on")
func requestedOnlyByOne() {
    #expect(StallMonitor.isRequested(["NEXUS_STALL_LOG": "1"]))
    #expect(!StallMonitor.isRequested(["NEXUS_STALL_LOG": "true"]))
    #expect(!StallMonitor.isRequested([:]))
}
```

`Mutex` is `Synchronization.Mutex`, available on macOS 15 only. The floor is macOS 14, so use `OSAllocatedUnfairLock` from `os` in both the test and the implementation. `waitUntil` lives in the UI test target; copy the file to `Tests/NexusCoreTests/WaitUntil.swift` if the core target has none.

- [ ] **Step 2: Run them, expect failure**

Run: `swift test --filter StallMonitorTests`
Expected: does not compile, `cannot find 'StallMonitor' in scope`.

- [ ] **Step 3: Implement `StallMonitor`**

A `DispatchSourceTimer` on a private utility queue. Each tick records `ContinuousClock.now`, and if no ping is outstanding, dispatches a block to `DispatchQueue.main` that clears the outstanding flag and reports `now - sent` when it is at or above `threshold`. One outstanding ping at a time, so one stall is one report.

- [ ] **Step 4: Wire it up**

In `Composition`, where services start: if `StallMonitor.isRequested()`, create one whose `report` logs `Log.system.notice("Main thread stalled \(milliseconds, privacy: .public) ms")`. Hold it in a stored property. Nothing is created when the variable is absent.

- [ ] **Step 5: Run tests, lint, commit**

Run: `swift test --filter StallMonitorTests && make lint`
Expected: PASS, `OK: zero warnings`.
`git commit -m "feat: stall monitor behind NEXUS_STALL_LOG"`

- [ ] **Step 6: Record the baseline**

```bash
make app && make stop
NEXUS_STALL_LOG=1 build/Nexus.app/Contents/MacOS/NexusApp &
```
(If the binary has another name, `ls build/Nexus.app/Contents/MacOS/`.) With music playing in Music or Spotify and the now-playing row on: move the pointer on and off the bar 20 times, open 5 window flyouts, leave the player's timeline on screen for 30 s. Then:

```bash
/usr/bin/log show --predicate 'subsystem == "com.congbui.nexus" AND eventMessage CONTAINS "stalled"' --last 5m --style compact
```
Write the count and the largest value into `docs/verification.md` under a new heading `## Stall baseline, 2026-11-16`. This run needs a person at the machine; if no one is there, say so in the report and leave the heading with "not measured".

---

### Task 2: Media script off the main thread

Today `NowPlayingService.swift:482` polls once a second while a timeline is on screen, and each poll compiles and runs an `NSAppleScript` on the main actor (`MediaPositionService.swift:169-200`).

**Files:**
- Create: `Sources/NexusCore/Media/ScriptRunner.swift`
- Modify: `Sources/NexusCore/Media/MediaPositionService.swift` (`AppleScriptMediaControl`: init, `playback`, `seek`, `command`; delete `runForReading` and `run`)
- Test: `Tests/NexusCoreTests/ScriptRunnerTests.swift`, and extend `Tests/NexusCoreTests/NowPlayingTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum ScriptOutcome: Sendable, Equatable {
      case values([Double])     // numbers and booleans (true = 1, false = 0), in order
      case empty                // ran, returned nothing usable
      case timedOut             // AppleScript error -1712
      case failed               // anything else
  }
  public protocol ScriptRunning: Sendable {
      func run(_ source: String) async -> ScriptOutcome
  }
  public final class AppleScriptRunner: ScriptRunning {
      public static let timeoutSeconds = 2
      public init()
  }
  ```
- Changes: `AppleScriptMediaControl.init(runner: any ScriptRunning = AppleScriptRunner())`.

**Decisions:**
- `AppleScriptRunner` owns one serial `DispatchQueue(label: "com.congbui.nexus.script", qos: .utility)`. Every `NSAppleScript` is created, compiled and executed on that queue and nowhere else. `run` bridges with `withCheckedContinuation`.
- Compiled scripts are cached in a dictionary keyed by source, touched only on that queue, capped at 32 entries (clear all when full). Seek scripts differ per position, so only sources without a digit-bearing argument are worth keeping: cache when the source is one of the `read` or `transport` strings, which the control passes with `cacheable: true`. Give `run` a defaulted second parameter on the concrete type only; the protocol keeps one parameter and the control calls the concrete method through a private helper. Simpler alternative allowed: cache every source and rely on the cap.
- The runner wraps each source before compiling:
  `"with timeout of 2 seconds\n" + source + "\nend timeout"`.
  Error number `-1712` in the error dictionary (`NSAppleScript.errorNumber`) maps to `.timedOut`.
- `NSAppleScript` is documented as main-thread-only. Confining it to one serial queue is the accepted trade (feature review, Improve 3). If the load runs in Step 6 crash inside `NSAppleScript`, replace the queue with one dedicated `Thread` and report it; do not move it back to the main actor.
- In `AppleScriptMediaControl`: `.timedOut` returns `nil` (or `false`) and does **not** add the player to `refused`. `.failed` and `.empty` refuse, as today. Three consecutive timeouts for one player refuse it for the session.
- Script sources stay the fixed strings in `dialects`. The only interpolated value is a `Double` or `Int`; keep it that way and never interpolate a string.
- The failure log stays at `.notice` and logs the error number only, not the error dictionary (it can contain the track name).

- [ ] **Step 1: Write the failing tests**

`ScriptRunnerTests.swift`, against the real runner with scripts that address no application (no Automation prompt):

```swift
@Test("Numbers and booleans come back in order")
func values() async {
    #expect(await AppleScriptRunner().run("return {1.5, 240, true}") == .values([1.5, 240, 1]))
}

@Test("A script that fails is reported as failed")
func failure() async {
    #expect(await AppleScriptRunner().run("error number -128") == .failed)
}

@Test("A script that times out does not block the main actor")
@MainActor func mainActorStaysFree() async {
    let runner = AppleScriptRunner()
    async let outcome = runner.run("delay 0.4\nreturn {1}")
    var ticks = 0
    let start = ContinuousClock.now
    while ContinuousClock.now - start < .milliseconds(300) {
        try? await Task.sleep(for: .milliseconds(10)); ticks += 1
    }
    #expect(ticks >= 15)            // the main actor kept running
    #expect(await outcome == .values([1]))
}
```

`NowPlayingTests.swift`, with a fake:

```swift
actor FakeScriptRunner: ScriptRunning {
    var outcomes: [ScriptOutcome]
    private(set) var sources: [String] = []
    init(_ outcomes: [ScriptOutcome]) { self.outcomes = outcomes }
    func run(_ source: String) async -> ScriptOutcome {
        sources.append(source)
        return outcomes.isEmpty ? .failed : outcomes.removeFirst()
    }
}

@Test("A timeout gives no reading and the player is asked again")
func timeoutDoesNotRefuse() async {
    let runner = FakeScriptRunner([.timedOut, .values([12, 240, 1])])
    let control = AppleScriptMediaControl(runner: runner)
    #expect(await control.playback(of: "com.apple.Music") == nil)
    #expect(await control.playback(of: "com.apple.Music")?.position.position == 12)
}

@Test("Three timeouts in a row refuse the player")
func threeTimeoutsRefuse() async {
    let runner = FakeScriptRunner([.timedOut, .timedOut, .timedOut, .values([1, 2, 1])])
    let control = AppleScriptMediaControl(runner: runner)
    for _ in 0..<3 { _ = await control.playback(of: "com.apple.Music") }
    #expect(await control.playback(of: "com.apple.Music") == nil)
    #expect(await runner.sources.count == 3)
}

@Test("A failure refuses at once; Spotify's milliseconds become seconds")
func failureRefusesAndSpotifyConverts() async {
    let failing = AppleScriptMediaControl(runner: FakeScriptRunner([.failed, .values([1, 2, 1])]))
    #expect(await failing.playback(of: "com.apple.Music") == nil)
    #expect(await failing.playback(of: "com.apple.Music") == nil)
    let spotify = AppleScriptMediaControl(runner: FakeScriptRunner([.values([30, 240_000, 1])]))
    #expect(await spotify.playback(of: "com.spotify.client")?.position.duration == 240)
}
```

- [ ] **Step 2: Run them, expect failure**

Run: `swift test --filter "ScriptRunnerTests|NowPlayingTests"`
Expected: does not compile, `cannot find type 'ScriptRunning'`.

- [ ] **Step 3: Implement `ScriptRunner.swift`**

Signatures as above. Reading the result: `numberOfItems > 0` gives a list, read `atIndex(1...n)`; a descriptor of type `typeTrue`/`typeFalse`/`typeBoolean` becomes 1 or 0, otherwise `doubleValue`. A scalar result becomes a one-element list. No items and no scalar is `.empty`.

- [ ] **Step 4: Change `AppleScriptMediaControl`**

`playback` needs exactly three values, else it refuses as for `.empty`. Add `private var timeouts: [String: Int]`, reset to 0 on any `.values`. Delete the two `@MainActor static` functions.

- [ ] **Step 5: Run tests and lint**

Run: `swift test && make lint`
Expected: all pass, `OK: zero warnings`.

- [ ] **Step 6: Load runs, then commit**

Three `swift test` runs under full load (see Global Constraints). Expected: three passes, no crash report in `~/Library/Logs/DiagnosticReports/` newer than the run.
`git commit -m "fix: media scripts run off the main thread, with a timeout"`

---

### Task 3: Hover refresh waits for the motion to settle

`SidebarViewModel.hoverChanged` (`SidebarViewModel.swift:1554`) starts three refreshes at the instant the expand begins; their results rebuild the rows mid-animation.

**Files:**
- Modify: `Sources/NexusUI/Sidebar/SidebarViewModel.swift:1554-1563`
- Modify: `Sources/NexusUI/Design/DesignMetrics.swift` (one constant)
- Test: `Tests/NexusUITests/SidebarViewModelTests.swift` (the existing tests near line 453 call `hoverChanged(true)` and expect an immediate refresh: change them to `waitUntil`)

**Interfaces:**
- Produces: `Design.settleDelay: Duration = .milliseconds(300)` and, on the model, `var hoverSettleDelay: Duration = Design.settleDelay` (a stored `@ObservationIgnored` property, so tests can pass `.milliseconds(20)`).

**Decision:** on hover-in, cancel any pending task and start one that sleeps `hoverSettleDelay`, then calls `refreshWindowCounts?()`, `refreshBadges?()`, `refreshTrash()`. On hover-out, cancel it. `setExpanded`, `endEditing` and `onHoverChange` keep their present order and timing.

- [ ] **Step 1: Write the failing tests**

```swift
@Test("Entering the bar refreshes after the settle delay, not before")
@MainActor func refreshWaits() async throws {
    let model = makeModel()                       // the file's existing helper
    model.hoverSettleDelay = .milliseconds(20)
    var counts = 0, badges = 0
    model.refreshWindowCounts = { counts += 1 }
    model.refreshBadges = { badges += 1 }
    model.hoverChanged(true)
    #expect(counts == 0 && badges == 0)
    try await waitUntil { counts == 1 && badges == 1 }
    #expect(counts == 1 && badges == 1)
}

@Test("Leaving before the settle delay cancels the refresh")
@MainActor func leavingCancels() async throws {
    let model = makeModel()
    model.hoverSettleDelay = .milliseconds(80)
    var counts = 0
    model.refreshWindowCounts = { counts += 1 }
    model.hoverChanged(true)
    model.hoverChanged(false)
    try await Task.sleep(for: .milliseconds(200))   // showing an absence: a sleep is right here
    #expect(counts == 0)
}
```

- [ ] **Step 2: Run, expect failure** — `swift test --filter SidebarViewModelTests`; `hoverSettleDelay` does not exist.
- [ ] **Step 3: Implement** as decided above.
- [ ] **Step 4: Fix the tests that expected an immediate refresh**, run `swift test && make lint`, expect all pass.
- [ ] **Step 5: Commit** — `git commit -m "fix: hover refresh waits until the bar has settled"`

---

### Task 4: The window takes its frame in one step; the content moves

Today: on hover-expand the window jumps to 220 pt (`PanelController.swift:90`, `animated: false`) while the content eases for 0.18 s (`SidebarView.swift:28`), so the background snaps and the labels fade. On auto-hide the window itself is animated (`PanelController.swift:951-960`), which resizes or moves the window, its blur and its SwiftUI layout on every frame.

After: the window is always given its *final or larger* frame in one step. The bar is drawn inside it at an animated width (expand) or an animated offset (auto-hide). When a motion ends in a smaller or hidden frame, the window is moved there afterwards.

**Files:**
- Create: `Sources/NexusUI/Sidebar/BarMotion.swift`
- Modify: `Sources/NexusUI/Sidebar/SidebarViewModel.swift` (two stored properties)
- Modify: `Sources/NexusUI/Sidebar/SidebarView.swift:16-32` (the body)
- Modify: `Sources/NexusUI/Panels/PanelController.swift` (`reframe`, `setFrame`, `reveal`, `scheduleHide`, line 90)
- Modify: `Sources/NexusUI/Design/DesignMetrics.swift` (`reveal`)
- Test: `Tests/NexusUITests/BarMotionTests.swift`, `Tests/NexusUITests/DesignTests.swift`

**Interfaces:**
- Produces:
  ```swift
  /// What the bar is drawn as inside its window. Pure, so it is tested without a window.
  public struct BarMotion: Equatable, Sendable {
      /// The bar's own thickness: `appearance.width` collapsed, `max(220, appearance.width)` expanded.
      public var thickness: CGFloat
      /// How far the bar is pushed toward its screen edge: 0 when revealed, thickness + screenMargin when hidden.
      public var offset: CGSize
      /// The window edge the bar is pinned to.
      public var alignment: Alignment

      public static func resolve(appearance: AppearanceConfiguration, expanded: Bool, hidden: Bool) -> BarMotion
      /// The window's thickness for a transition between two states: the larger of the two.
      public static func windowExpanded(from: Bool, to: Bool) -> Bool   // returns from || to
  }
  ```
  `alignment`: `.leading` for `.left`, `.trailing` for `.right`, `.top` for `.top`, `.bottom` for `.bottom`. `offset` points off screen: negative x for `.left`, positive x for `.right`, negative y for `.top`, positive y for `.bottom` (SwiftUI's y grows downward).
- Produces on `SidebarViewModel`: `public var isBarHidden = false` (observed; drives the offset) and `public var windowIsExpanded = false` (observed; what size the window currently is, set by `PanelController` only).
- Changes: `Design.reveal = Animation.spring(duration: 0.26, bounce: 0)`.
- Changes: `PanelController.reframe(animated:)` keeps its signature. Its `animated` parameter no longer animates a window; it selects whether the content motion is animated.

**Decisions:**

Window frame rule, in `reframe`: size the window with `expanded: model.windowIsExpanded` and `hidden: false` whenever the bar should be on screen or is still sliding; `hidden: true` only once a hide has finished.

Sequences. "Shrink step" means: `model.windowIsExpanded = false`, set the frame, `invalidateShadow()`.

| Event | Now | When the content animation completes |
|---|---|---|
| Expand | `windowIsExpanded = true`; set the wide frame; `invalidateShadow()`; `isExpanded = true` animates the content | nothing |
| Collapse | `isExpanded = false` animates the content; the window stays wide | shrink step, **only if `isExpanded` is still false** |
| Reveal | set the on-screen frame; order front; `isBarHidden = false` animates the offset | nothing |
| Hide | `isBarHidden = true` animates the offset; the window stays | set the parked frame (`hidden: true`), **only if `isBarHidden` is still true** |

The "still" checks are what make an interrupted motion safe: a collapse that was overtaken by a new expand must not shrink the window under it.

Completion: wrap the state change in `withAnimation(Design.animation(Design.reveal, reduceMotion:) , completionCriteria: .logicallyComplete) { … } completion: { … }` (macOS 14). With Reduce Motion the animation is `nil`: run the state change and the completion step synchronously, in that order.

`layoutDidChange?()` has five callers in `SidebarViewModel.swift`; only the one in `setExpanded` is about expansion. Add a second closure on the model, `@ObservationIgnored public var expansionWillChange: ((Bool) -> Void)?`. `setExpanded` stops assigning `isExpanded` itself when the closure is set: it calls `expansionWillChange?(next)` and the controller assigns `model.isExpanded` inside its `withAnimation`, per the table. When the closure is `nil` (tests that build a model without a controller), `setExpanded` assigns `isExpanded` and calls `layoutDidChange?()` as today, so existing model tests keep passing. The other four callers keep `layoutDidChange`, which stays wired to `reframe(animated: false)`. `isExpanded` needs a setter the controller can reach: it is already `public var`.

In `SidebarView.body`, replace `.frame(maxWidth: .infinity, maxHeight: .infinity)` on the bar with a fixed thickness and pin it to its edge inside the window:

```swift
let motion = BarMotion.resolve(appearance: model.appearance, expanded: model.isExpanded, hidden: model.isBarHidden)
bar                                           // content + background + clip + border + opacity, as today
    .frame(width: isVertical ? motion.thickness : nil, height: isVertical ? nil : motion.thickness)
    .offset(motion.offset)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: motion.alignment)
```

Delete `.animation(…, value: model.isExpanded)` from the body: the animation now comes from the `withAnimation` in `PanelController`, so there is exactly one clock. `.onHover` stays on the bar, not on the outer frame, so the transparent part of a wide window does not count as "over the bar".

Delete the `NSAnimationContext` branch of `PanelController.setFrame`; it becomes `panel.setFrame(frame, display: true)`. The pointer-follows-display reframe (`pointerMoved`) therefore jumps instead of sliding between monitors. That is intended: a 0.18 s cross-monitor window slide was the same per-frame resize.

Reserved Space reads `bar.frame` through `reservedSpaceGeometries`. During a collapse the window is still wide for 0.26 s, so Reserved Space would push windows off a strip that is about to be free. Call `onBarFrameChange?()` only after a frame is actually set, which the table already does: the shrink step sets the frame and `reframe` already ends with `onBarFrameChange?()`.

Flyouts anchor to `sidebar.frame` (`layoutFlyout` and its siblings). They open only while the pointer is on the bar, when the window and the bar have the same frame, so they need no change.

- [ ] **Step 1: Write the failing tests**

`BarMotionTests.swift`:

```swift
@Test("Thickness follows the expanded state, never below the configured width")
func thickness() {
    var a = AppearanceConfiguration(); a.position = .left; a.width = 64
    #expect(BarMotion.resolve(appearance: a, expanded: false, hidden: false).thickness == 64)
    #expect(BarMotion.resolve(appearance: a, expanded: true, hidden: false).thickness == 220)
    a.width = 260
    #expect(BarMotion.resolve(appearance: a, expanded: true, hidden: false).thickness == 260)
}

@Test("A hidden bar is pushed off its own edge by its thickness plus the margin",
      arguments: [(SidebarPosition.left, CGSize(width: -72, height: 0), Alignment.leading),
                  (.right, CGSize(width: 72, height: 0), .trailing),
                  (.top, CGSize(width: 0, height: -72), .top),
                  (.bottom, CGSize(width: 0, height: 72), .bottom)])
func hiddenOffset(position: SidebarPosition, offset: CGSize, alignment: Alignment) {
    var a = AppearanceConfiguration(); a.position = position; a.width = 64
    let hidden = BarMotion.resolve(appearance: a, expanded: false, hidden: true)
    #expect(hidden.offset == offset)                 // 64 + SidebarLayout.screenMargin (8)
    #expect(hidden.alignment == alignment)
    #expect(BarMotion.resolve(appearance: a, expanded: false, hidden: false).offset == .zero)
}

@Test("The window is wide for the whole of any transition that touches the expanded state")
func windowSize() {
    #expect(BarMotion.windowExpanded(from: false, to: true))
    #expect(BarMotion.windowExpanded(from: true, to: false))
    #expect(!BarMotion.windowExpanded(from: false, to: false))
}
```

If `AppearanceConfiguration` cannot be built with `init()` or names these fields differently, read `Sources/NexusCore/Configuration/NexusConfiguration.swift` and use the real ones; the values (64, 220, 8) stand. Horizontal bars never expand (D53), so for `.top`/`.bottom` `expanded: true` must still return `appearance.width`: add that assertion.

In `DesignTests.swift`, the controller behaviour, driven through a real `PanelController` the way `DisplayAndRecoveryTests.swift` builds one (copy its setup):

```swift
@Test("Collapse during expand ends at the collapsed frame")      // expand, collapse at once, waitUntil windowIsExpanded == false
@Test("Expand during collapse keeps the window wide")            // expand, wait, collapse, expand at once, wait 400 ms, windowIsExpanded == true
@Test("Reduce motion shrinks the window at once")                // inject reduceMotion: true, collapse, windowIsExpanded == false synchronously
@Test("Hide parks every bar")                                    // autoHide on, hide, waitUntil each bar frame == SidebarLayout.frame(..., hidden: true)
```

Reduce Motion must be injectable for the third test: add `var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }` to `PanelController` and read it everywhere this task gates an animation. For the fourth, expose `var barFrames: [CGRect] { bars.map(\.frame) }` as `internal`.

- [ ] **Step 2: Run, expect failure** — `swift test --filter "BarMotionTests|DesignTests"`; `BarMotion` does not exist.
- [ ] **Step 3: Implement `BarMotion.swift`** — pure functions, no AppKit.
- [ ] **Step 4: Add the two model properties and change `SidebarView.body`** as decided.
- [ ] **Step 5: Change `PanelController`** per the table: `expansionChanged()`, `reveal()`, `scheduleHide()`, `reframe`, `setFrame`.
- [ ] **Step 6: Change `Design.reveal`**, and the assertion in `DesignTests.swift` that pins its old value, if there is one.
- [ ] **Step 7: Run everything** — `swift test && make lint`, expect all pass and zero warnings. Then three runs under load.
- [ ] **Step 8: Commit** — `git commit -m "fix: the bar's content animates inside a window that takes its frame once"`

---

### Task 5: Measure again, and hand over to the owner

**Files:**
- Modify: `docs/verification.md`, `docs/release-checklist.md`, `CHANGELOG.md`

- [ ] **Step 1: Repeat Task 1 Step 6 exactly** and write the numbers under `## Stall result, week 1`. Pass: no stall of 50 ms or more during hover, expand, collapse, reveal or hide, and none at one-second intervals while a timeline is showing. A stall that remains is reported with what was on screen; it is not explained away.
- [ ] **Step 2: Add checklist rows** to `docs/release-checklist.md`, in the file's own row format:
  - Hover-expand on a left bar and on a right bar: background and labels move together; no jump.
  - Leave the bar halfway through the expand: it turns round smoothly; the window ends narrow (a window under where the wide bar was can be clicked).
  - Auto-hide: the bar slides out and back; with a bar on every display, all of them.
  - Reduce Motion on: expand, collapse, hide and reveal are immediate; nothing is left wide or half hidden.
  - Shadow follows the bar after expand and after collapse (no shadow in the shape of the old size).
  - Music playing in Music, then in Spotify, timeline visible for a minute: the bar's hover highlight never freezes.
  - Quit the player while its timeline is showing: the timeline goes; the bar does not hang.
- [ ] **Step 3: `CHANGELOG.md`**: under an `Unreleased` heading, three lines: media scripts off the main thread; bar motion; hover refresh.
- [ ] **Step 4: Commit and merge**

```bash
git commit -am "docs: week 1 stall numbers and checklist rows"
git checkout main && git merge --no-ff feat/smooth-bar
```

- [ ] **Step 5: Report to the owner.** State the two stall numbers side by side, list any checklist row that could not be confirmed without a person, and stop. Week 2 (`2026-11-16-dock-habits-weeks2-3.md`) starts only when the owner has looked at the bar and said it is better.

## Not in this plan

- Row redraw isolation, springs on rows, flyout fades, press feedback: weeks 2 and 3.
- Icon pre-rendering: only if the week 1 result still shows stalls during scroll.
- The eleven removals in the feature review: the owner has not accepted them.
