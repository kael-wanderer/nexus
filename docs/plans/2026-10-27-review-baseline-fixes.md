# Review baseline fixes — implementation plan

> **For agentic workers:** execute task by task, in order. Every step uses checkbox (`- [ ]`)
> syntax. Do not make design decisions: if something in the code does not match what a step
> says, stop and report instead of improvising.

**Goal:** Fix the confirmed findings of the 2026-10-27 app review that are cheap and certain:
newer configuration being overwritten (R1), a settings search entry that opens the wrong tab (R3),
a flyout race that shows stale windows after Accessibility is revoked (R2, the flaky test), a test
warning, a settings window that does not fit an 800-point-tall screen (R6), and three inaccurate
README claims (R8).

**Architecture:** Small, local edits. The store refuses its own writes after a newer-version load;
the flyout re-checks the permission after its `await`; the settings frame gets a flexible height
and the window is clamped to the screen.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Swift Testing (`import Testing`), SwiftPM. Commands run
from the repo root `/Users/cong.bui/Kael/19-AppBuild/Nexus`.

**Spec:** `docs/reviews/2026-10-27-app-review-and-improvement-plan.md` (findings R1, R2, R3, R6,
R8), narrowed by Claude's review of it in the same session. Out of scope: R4, R5, R7, the R3
scroll-to-control work, the R6 sidebar redesign, CI, notarisation.

## Global Constraints

- Branch: `fix/review-baseline`, created from `main`. Never commit to `main`.
- Do not touch `docs/reviews/` (untracked, owner's file).
- Match the surrounding style: doc comments explain *why*, British spelling in comments
  ("behaviour", "colour"), `String(localized:)` for user-visible strings.
- No new dependencies. No new files except where a task says "Create".
- `make lint` must report zero warnings at the end (it builds tests too).
- Commit messages: Conventional Commits, lowercase, as in `git log` (`fix: …`, `test: …`, `docs: …`).

## Review Focus

1. A newer configuration must survive *every* write path: the startup `flush()`, the 250 ms
   debounced save after an edit, and the terminate `flush()` — Task 1's test drives all three.
2. A first launch with nothing stored must still write the defaults (Composition relies on it to
   make the configuration inspectable with `defaults`) — Task 1, second test.
3. A window load that finishes after a revocation must not repopulate the flyout — Task 3's
   deterministic test, not only the timing-based existing one.
4. Settings window on a small screen: it must open fully on screen and the panes must scroll —
   Task 5 manual check.
5. Search for "position" must land on the Dock tab, and still find exactly one entry — Task 2.

---

### Task 0: Branch

- [x] **Step 1:** `git checkout main && git pull --ff-only && git checkout -b fix/review-baseline`
- [x] **Step 2:** `swift build` — expected: `Build complete!`

---

### Task 1: A newer configuration is never overwritten (R1)

**Files:**
- Modify: `Sources/NexusCore/Configuration/ConfigurationStore.swift`
- Test: `Tests/NexusCoreTests/ConfigurationTests.swift`

**Why:** `ConfigurationStore.loadThrowing` returns defaults for a newer schema and promises to
leave the bytes alone (D10), but `Composition.start()` calls `configuration.flush()` at launch and
`save` writes unconditionally, so the newer file is replaced on the first launch of an older build.

- [x] **Step 1: Write the failing tests.** In `ConfigurationTests.swift`, directly after the
existing `newerVersion()` test (ends around line 163), add:

```swift
    /// D10 is only kept if nothing writes afterwards: `Composition.start()` flushes on launch,
    /// every edit schedules a save, and terminate flushes again.
    @Test("A newer-versioned configuration survives the launch flush, an edit and the quit flush")
    @MainActor
    func newerVersionSurvivesWrites() async throws {
        let defaults = makeDefaults()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(NexusConfiguration())) as! [String: Any]
        json["version"] = NexusConfiguration.currentVersion + 1
        let raw = try JSONSerialization.data(withJSONObject: json)
        defaults.set(raw, forKey: ConfigurationStore.defaultKey)

        let store = ConfigurationStore(defaults: defaults)
        let controller = ConfigurationController(store: store, events: EventBus(), saveDelay: .milliseconds(10))

        controller.flush()
        #expect(defaults.data(forKey: ConfigurationStore.defaultKey) == raw)

        controller.update { $0.appearance.position = .bottom }
        try await Task.sleep(for: .milliseconds(100))
        #expect(defaults.data(forKey: ConfigurationStore.defaultKey) == raw)
        // The edit still applies for this session — it just is not written over the newer file.
        #expect(controller.configuration.appearance.position == .bottom)

        controller.flush()
        #expect(defaults.data(forKey: ConfigurationStore.defaultKey) == raw)
    }

    @Test("With nothing stored, the launch flush still writes the defaults")
    @MainActor
    func firstLaunchStillWrites() throws {
        let defaults = makeDefaults()
        let controller = ConfigurationController(store: ConfigurationStore(defaults: defaults), events: EventBus())
        controller.flush()
        let data = try #require(defaults.data(forKey: ConfigurationStore.defaultKey))
        #expect(try JSONDecoder().decode(NexusConfiguration.self, from: data) == NexusConfiguration())
    }
```

- [x] **Step 2: Run, expect failure.**
Run: `swift test --filter ConfigurationTests`
Expected: `newerVersionSurvivesWrites` FAILS (the stored data no longer equals `raw`);
`firstLaunchStillWrites` PASSES.

- [x] **Step 3: Implement.** In `ConfigurationStore.swift`:

  a. Below `nonisolated(unsafe) private var lastOutcome …` add:

```swift
    /// Set when the stored configuration came from a newer Nexus: from then on `save` writes
    /// nothing, so neither the launch flush nor a later edit replaces bytes this build cannot read
    /// (D10). The session runs on defaults in memory; the newer build finds its file intact.
    nonisolated(unsafe) private var preservesStoredBytes = false
```

  b. Replace the body of `save(_:)` with:

```swift
    public func save(_ configuration: NexusConfiguration) throws {
        lock.lock()
        let preserves = preservesStoredBytes
        lock.unlock()
        guard !preserves else {
            Log.app.notice("Configuration not saved: the stored one is from a newer Nexus")
            return
        }
        var stored = configuration
        stored.version = NexusConfiguration.currentVersion
        stored.appearance.clamp()
        let data = try JSONEncoder().encode(stored)
        defaults.set(data, forKey: key)
    }
```

  c. Replace `record(_:)` with:

```swift
    private func record(_ outcome: ConfigurationLoadOutcome) {
        lock.lock()
        lastOutcome = outcome
        if case .newerVersionIgnored = outcome {
            preservesStoredBytes = true
        } else {
            preservesStoredBytes = false
        }
        lock.unlock()
    }
```

  d. Update the comment inside `loadThrowing` from
  `// A newer Nexus wrote this. Run defaults in memory; leave the bytes untouched (D10).` to
  `// A newer Nexus wrote this. Run defaults in memory; leave the bytes untouched (D10) — `
  `// \`record\` also stops \`save\` from writing for the rest of the session.`
  (two comment lines).

- [x] **Step 4: Run, expect pass.**
Run: `swift test --filter ConfigurationTests`
Expected: all ConfigurationTests pass, including the two new ones and the existing `newerVersion`,
`roundTrip` and migration tests.

- [x] **Step 5: Commit.**
```bash
git add Sources/NexusCore/Configuration/ConfigurationStore.swift Tests/NexusCoreTests/ConfigurationTests.swift
git commit -m "fix: never write over a configuration from a newer Nexus"
```

---

### Task 2: "Position" opens the Dock tab (R3)

**Files:**
- Modify: `Sources/NexusUI/Settings/SettingsSearch.swift` (the `entries` array)
- Test: `Tests/NexusUITests/SettingsSearchTests.swift`

**Why:** `SidebarPositionPicker` is drawn in `DockPane` (`SettingsView.swift:224`), but the index
lists Position under `.appearance`, so the result opens a tab without the control. An audit of
every other entry against the panes found no other wrong tab.

- [x] **Step 1: Write the failing test.** Add to `SettingsSearchTests`, after `findsByTitleAndKeyword`:

```swift
    /// The edge picker lives with the rest of the Dock placement controls, not in Appearance.
    @Test("Position takes you to the Dock tab, where the edge picker is")
    func positionRoutesToDock() {
        let results = SettingsSearch.matches("position")
        #expect(results.map(\.title) == ["Position"])
        #expect(results.first?.tab == .dock)
    }
```

- [x] **Step 2: Run, expect failure.**
Run: `swift test --filter SettingsSearchTests`
Expected: `positionRoutesToDock` FAILS (`.appearance` is not `.dock`).

- [x] **Step 3: Implement.** In `SettingsSearch.entries`:
  - Delete the line
    `SettingsEntry(String(localized: "Position"), "edge left right top bottom", .appearance),`
    from the `// Appearance` block.
  - Add, as the last line of the `// Dock` block (after the `"Display"` entry):
    `SettingsEntry(String(localized: "Position"), "edge left right top bottom", .dock),`

- [x] **Step 4: Run, expect pass.**
Run: `swift test --filter SettingsSearchTests`
Expected: all pass, including `uniqueEntries` and `everyTabIndexed` (Appearance still has entries).

- [x] **Step 5: Commit.**
```bash
git add Sources/NexusUI/Settings/SettingsSearch.swift Tests/NexusUITests/SettingsSearchTests.swift
git commit -m "fix: settings search sends Position to the Dock tab"
```

---

### Task 3: A load in flight cannot undo a revocation (R2 flaky test)

**Files:**
- Modify: `Sources/NexusUI/Sidebar/WindowFlyoutViewModel.swift` (`reload()`, around line 107–119)
- Modify: `Tests/NexusUITests/WindowFlyoutTests.swift` (`FakeWindowService`, line 8 onwards)
- Test: `Tests/NexusUITests/DisplayAndRecoveryTests.swift` (`RevocationTests`)

**Why:** `show()` starts `Task { await reload() }`. If Accessibility is revoked while that load is
suspended in `service.windows(for:)`, the event handler clears `windows`, then the old load
resumes and assigns its result — stale windows behind the grant prompt. This is what made
`RevocationTests.flyoutDegrades` fail intermittently (`DisplayAndRecoveryTests.swift:133`,
`model.windows.isEmpty → false`).

- [x] **Step 1: Give the fake a way to hold one call.** In `FakeWindowService`
(`WindowFlyoutTests.swift`), add these stored properties under `private var trusted: Bool`:

```swift
    private var holdsNextWindowsCall = false
    private var heldCall: CheckedContinuation<Void, Never>?
    private var heldCallWaiters: [CheckedContinuation<Void, Never>] = []
```

add these methods after `setWindows(_:for:)`:

```swift
    /// The next `windows(for:)` suspends until `releaseHeldCall()`, so a test can change the
    /// world while a load is in flight.
    func holdNextWindowsCall() { holdsNextWindowsCall = true }

    func waitUntilCallIsHeld() async {
        if heldCall != nil { return }
        await withCheckedContinuation { heldCallWaiters.append($0) }
    }

    func releaseHeldCall() {
        heldCall?.resume()
        heldCall = nil
    }
```

and make the first lines of `windows(for:)`:

```swift
    func windows(for application: ApplicationIdentity) async throws -> [NexusWindow] {
        if holdsNextWindowsCall {
            holdsNextWindowsCall = false
            await withCheckedContinuation { continuation in
                heldCall = continuation
                heldCallWaiters.forEach { $0.resume() }
                heldCallWaiters = []
            }
        }
        guard trusted else { throw NexusError.permissionDenied(.accessibility) }
        return byApplication[application.bundleIdentifier] ?? []
    }
```

- [x] **Step 2: Write the failing test.** In `DisplayAndRecoveryTests.swift`, inside
`struct RevocationTests`, directly after `flyoutDegrades()`:

```swift
    @Test("A window load still in flight when Accessibility is revoked does not put its windows back")
    func revocationDuringLoad() async throws {
        let bus = EventBus()
        let permissions = FakePermissions([.accessibility: .granted])
        let identity = ApplicationIdentity(bundleIdentifier: "com.apple.Safari")
        let service = FakeWindowService([
            "com.apple.Safari": [
                NexusWindow(
                    identity: WindowIdentity(owner: identity, number: 1),
                    title: "GitHub",
                    applicationName: "Safari"
                )
            ]
        ])
        await service.holdNextWindowsCall()
        let model = WindowFlyoutViewModel(
            service: service,
            previewService: FakePreviewService(),
            permissions: permissions,
            events: bus
        )
        model.start()
        defer { model.stop() }
        model.show(identity, name: "Safari")
        await service.waitUntilCallIsHeld()

        permissions.statuses[.accessibility] = .denied
        bus.publish(.permissionChanged(.accessibility, .denied))
        var waited = 0
        while !model.showsPermissionRequest && waited < 100 {
            try await Task.sleep(for: .milliseconds(5))
            waited += 1
        }
        #expect(model.showsPermissionRequest)

        await service.releaseHeldCall()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.windows.isEmpty)
    }
```

- [x] **Step 3: Run, expect failure.**
Run: `swift test --filter RevocationTests`
Expected: `revocationDuringLoad` FAILS on `model.windows.isEmpty` (one window, "GitHub").

- [x] **Step 4: Implement.** In `WindowFlyoutViewModel.reload()`, replace
`guard self.target == target else { return }` with:

```swift
        // Both can change while the load was suspended: a different application's flyout, or a
        // revocation that already cleared the list — writing this result would put it back.
        guard self.target == target, accessibility == .granted else { return }
```

- [x] **Step 5: Run, expect pass.**
Run: `swift test --filter RevocationTests` — expected: all pass.
Run: `swift test --filter WindowFlyout` — expected: all pass (the fake change is additive).

- [x] **Step 6: Commit.**
```bash
git add Sources/NexusUI/Sidebar/WindowFlyoutViewModel.swift Tests/NexusUITests/WindowFlyoutTests.swift Tests/NexusUITests/DisplayAndRecoveryTests.swift
git commit -m "fix: a window load that finishes after a revocation is dropped"
```

---

### Task 4: Remove the redundant `#require` warning

**Files:**
- Modify: `Tests/NexusUITests/ClockAndVolumeTests.swift:103-110` (`sectionIndicesFollowWhatIsDrawn`)

- [x] **Step 1: Implement.** Replace the function with:

```swift
    func sectionIndicesFollowWhatIsDrawn() throws {
        let (model, controller) = makeModel()
        let volumeSection = try #require(model.volumeSectionIndex)
        #expect(model.clockSectionIndex == volumeSection + 1)
        controller.update { $0.general.showVolume = false }
        #expect(model.volumeSectionIndex == nil)
        #expect(model.clockSectionIndex == volumeSection)
    }
```

Keep the `@Test(…)` line and doc comment above it unchanged.

- [x] **Step 2: Verify.**
Run: `swift test --filter ClockAndVolume` — expected: all pass.
Run: `make lint` — expected: no `warning:` lines; exits 0.

- [x] **Step 3: Commit.**
```bash
git add Tests/NexusUITests/ClockAndVolumeTests.swift
git commit -m "test: drop the redundant try? around #require"
```

---

### Task 5: The settings window fits an 800-point screen (R6)

**Files:**
- Modify: `Sources/NexusUI/Settings/SettingsView.swift:42-45`
- Modify: `Sources/NexusUI/Settings/AuxiliaryWindowController.swift` (`makeWindow()`)

**Why:** `.frame(width: 620, height: 790)` pins the content, so the "resizable" window cannot
actually shrink; on a 1280×800 display 790 plus the title bar does not fit under the menu bar.
Keeping 790 as the *ideal* height preserves the no-scroll behaviour wherever it fits; the
`.grouped` Forms scroll by themselves when the window is shorter.

- [x] **Step 1: Implement the frame.** In `SettingsView.body`, replace the comment and
`.frame(width: 620, height: 790)` with:

```swift
        // Sized for the longest pane rather than the average one: a settings window that scrolls
        // hides the switch somebody came looking for. 790 is only the ideal, though — on a screen
        // too short for it the window opens shorter and the pane scrolls, rather than running
        // off the bottom.
        .frame(minWidth: 620, idealWidth: 620, minHeight: 420, idealHeight: 790)
```

- [x] **Step 2: Clamp the initial window to the screen.** In `AuxiliaryWindowController.makeWindow()`,
replace `contentRect: NSRect(origin: .zero, size: hosting.fittingSize),` with
`contentRect: NSRect(origin: .zero, size: fittingScreen(hosting.fittingSize)),`
and add this method to the class, after `makeWindow()`:

```swift
    /// The content's ideal size, cut down to what the screen can show below the menu bar with a
    /// title bar on top — `center()` cannot move a window that is taller than the screen.
    private func fittingScreen(_ size: NSSize) -> NSSize {
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return size }
        let titleBar: CGFloat = 32
        return NSSize(width: min(size.width, visible.width), height: min(size.height, visible.height - titleBar))
    }
```

- [x] **Step 3: Verify build and tests.**
Run: `swift build` — expected: `Build complete!`
Run: `swift test --filter Settings` — expected: all pass.

- [x] **Step 4: Commit.**
```bash
git add Sources/NexusUI/Settings/SettingsView.swift Sources/NexusUI/Settings/AuxiliaryWindowController.swift
git commit -m "fix: the settings window opens on screen when the screen is short"
```

Manual check (owner or reviewer, not Luna): `make run`, open Settings on the large display —
the window is 790 tall with no scrolling, as before; resize it shorter — the pane scrolls.
Known risk for the reviewer: `NSHostingView`'s default `sizingOptions` turn the ideal size into
an intrinsic-size constraint, which may still stop the window shrinking. If so, the follow-up is
`hosting.sizingOptions = [.minSize]` for the settings window only — check onboarding is unchanged.

---

### Task 6: README claims match the app (R8)

**Files:**
- Modify: `README.md` lines 6–9 and 223–225

- [x] **Step 1: Implement.** Replace lines 5–9:

```markdown
A native macOS vertical dock and a unified search palette in one agent application. Nexus runs
in the menu bar, never takes focus away from what you are typing in, and never changes a single
system setting on your behalf.

> Status: Milestones 1–23 shipped — the MVP and sixteen milestones past it. Local builds only —
```

with:

```markdown
A native macOS vertical dock and a unified search palette in one agent application. Nexus runs
in the menu bar, never takes focus away from what you are typing in, and changes no system
setting unless you ask it to replace the Dock — and then puts the Dock back exactly as it was.

> Status: Milestones 1–27 shipped — the MVP and twenty milestones past it. Local builds only —
```

(the line after the status line, `> see [Installation](#installation).`, stays.)

Replace:

```markdown
  parameters notification. There is exactly one poll in the whole app: permission status at 1 Hz
  while a permission screen is on screen, because macOS publishes no TCC notification.
```

with:

```markdown
  parameters notification. There is exactly one poll in the whole app: permission status at 1 Hz
  while a permission screen is on screen, because macOS publishes no TCC notification. (The
  clock redraws once a minute on SwiftUI's own `TimelineView` schedule.)
```

- [x] **Step 2: Verify.** `rg -n "Milestones 1–2" README.md` — expected: two lines, both `1–27`.

- [x] **Step 3: Commit.**
```bash
git add README.md
git commit -m "docs: README status and claims match the app"
```

---

### Task 7: Full verification

- [x] **Step 1:** `make lint` — expected: exits 0, no `warning:` lines.
- [x] **Step 2:** Run the full suite three times:
  `for i in 1 2 3; do swift test 2>&1 | rg "Fatal|signal|recorded an issue|Test run with"; echo "--"; done`
  Expected: every run prints only `Test run with … passed` lines (one per test library).
- [x] **Step 3:** If any run shows `Fatal error`, `signal`, or `recorded an issue`: do NOT fix it.
  Re-run that once with `swift test 2>&1 | tail -80 > /tmp/nexus-test-failure.txt` and report the
  file contents with the branch. (The review saw an `Index out of range` crash that did not
  reproduce under `--filter NexusUITests`; it may only appear in the full run.)
- [x] **Step 4:** Report: branch name, `git log --oneline main..HEAD`, test counts from Step 2,
  and anything that did not match this plan.

---

### Task 8: The search-selection test waits for results instead of guessing (follow-up from review)

**Files:**
- Modify: `Tests/NexusUITests/SearchSelectionTests.swift`

**Why:** the full-run `Fatal error: Index out of range` (signal 5) is this test, not the app. The
crash report puts it at `SearchSelectionTests.keyboardSelectionSurvivesLaterSnapshot()`, line 102:
`model.results[1]` after a fixed 80 ms sleep. When the machine is busy (the full suite runs both
test libraries in parallel), the first snapshot has not arrived yet, `results` is empty, and the
subscript traps, which kills the whole test process. Reproduced 4 runs out of 5 under CPU load.
`rowZeroPreselected()` has the same shape (`model.results[1]` after a fixed 200 ms).

- [x] **Step 1: Add a wait helper.** In `SearchSelectionTests.swift`, directly after the
`makeSearch(_:)` function (before `@Suite("Search selection stability")`), add:

```swift
/// Waits until the model shows at least `count` results — a fixed sleep guesses how long the
/// providers take, and on a busy machine the guess is wrong and `results[1]` traps.
@MainActor
private func waitForResults(
    _ model: SearchViewModel,
    count: Int,
    timeout: Duration = .seconds(2)
) async throws {
    let deadline = ContinuousClock.now + timeout
    while model.results.count < count, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(model.results.count >= count)
}
```

- [x] **Step 2: Fix `keyboardSelectionSurvivesLaterSnapshot()`.** Replace its body with:

```swift
        let model = makeSearch([
            DelayedProvider(identifier: .application, category: .application, titles: ["One", "Two"], score: 0.95),
            DelayedProvider(
                identifier: .file,
                category: .file,
                delay: .milliseconds(500),
                titles: ["a file"],
                score: 0.10
            ),
        ])
        model.query = "o"
        try await waitForResults(model, count: 2)
        // The file snapshot has to land *after* the arrow key, or this tests nothing.
        #expect(model.results.count == 2)
        model.moveSelection(by: 1)
        let chosen = model.selectedID
        #expect(chosen == model.results[1].id)

        try await waitForResults(model, count: 3)
        #expect(model.selectedID == chosen)
```

(The file delay goes from 150 to 500 ms so the late snapshot still arrives after the arrow key
on a slow machine. Keep the `@Test(…)` line and the `func` line unchanged.)

- [x] **Step 3: Fix `rowZeroPreselected()`.** Replace only its first
`try await Task.sleep(for: .milliseconds(200))` (the one right after `model.query = "o"`) with
`try await waitForResults(model, count: 2)`. Leave the second sleep, after `model.query = "on"`,
as it is.

- [x] **Step 4: Verify on a quiet machine.**
Run: `swift test --filter SearchSelectionTests` — expected: all pass.

- [x] **Step 5: Verify under load (this is what used to crash).** Run exactly:

```bash
for n in $(seq 1 $(sysctl -n hw.ncpu)); do (yes > /dev/null &); done
for i in 1 2 3 4 5; do swift test > /tmp/nexus-load-$i.txt 2>&1; echo "run $i exit $?"; rg -c "Fatal|recorded an issue" /tmp/nexus-load-$i.txt; done
pkill -x yes
```

Expected: five lines `run N exit 0`, and no count printed after any of them. Always run the
`pkill -x yes` line, even if a run fails. If any run fails, report that run's
`rg -n -B2 -A8 "Fatal|recorded an issue" /tmp/nexus-load-N.txt` output and stop.

- [x] **Step 6:** `make lint` — expected: exits 0, no warnings.

- [x] **Step 7: Commit.**
```bash
git add Tests/NexusUITests/SearchSelectionTests.swift docs/plans/2026-10-27-review-baseline-fixes.md
git commit -m "test: wait for search results instead of a fixed sleep"
```

**Review note on Task 8 Step 5 (2026-10-27):** the one failure under load was
`WindowFlyoutTests.grantWhileOpen` (`WindowFlyoutTests.swift:248`), a different test with the
same fixed-sleep weakness; the search crash itself is gone in all five runs. Task 8 is accepted:
run its Step 6 (`make lint`) and Step 7 (commit) now, then do Task 9.

---

### Task 9: Permission tests wait for the event's effect (follow-up from review)

**Files:**
- Create: `Tests/NexusUITests/WaitUntil.swift`
- Modify: `Tests/NexusUITests/WindowFlyoutTests.swift` (`grantWhileOpen()`, around line 246)
- Modify: `Tests/NexusUITests/DisplayAndRecoveryTests.swift` (`flyoutDegrades()` around line 130, `revocationDuringLoad()`)

**Why:** these tests publish a permission event, sleep a fixed 150 ms, then check its effect.
With every core busy the event takes longer than 150 ms and the check fails
(`model.windows.count → 0`). They should wait for the effect, with a generous timeout.

- [ ] **Step 1: Create `Tests/NexusUITests/WaitUntil.swift`** with exactly:

```swift
import Foundation

/// Polls until `condition` holds or `timeout` passes, for a state an event *will* produce — a
/// fixed sleep guesses how long that takes, and on a busy machine the guess is wrong. It does not
/// fail by itself: the caller's `#expect` says what was wanted. Never use it to show that
/// something does *not* happen; that still needs a sleep.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}
```

- [ ] **Step 2: `grantWhileOpen()`** in `WindowFlyoutTests.swift`: replace the line
`try await Task.sleep(for: .milliseconds(150))` (right after
`bus.publish(.permissionChanged(.accessibility, .granted))`) with
`try await waitUntil { model.windows.count == 1 }`. Keep the `#expect` after it.

- [ ] **Step 3: `flyoutDegrades()`** in `DisplayAndRecoveryTests.swift`: replace the line
`try await Task.sleep(for: .milliseconds(150))` (right after
`bus.publish(.permissionChanged(.accessibility, .denied))`) with
`try await waitUntil { model.showsPermissionRequest && model.windows.isEmpty }`. Keep both
`#expect` lines after it.

- [ ] **Step 4: `revocationDuringLoad()`** in the same file: replace these five lines

```swift
        var waited = 0
        while !model.showsPermissionRequest && waited < 100 {
            try await Task.sleep(for: .milliseconds(5))
            waited += 1
        }
```

with `try await waitUntil { model.showsPermissionRequest }`. Leave the
`try await Task.sleep(for: .milliseconds(50))` after `releaseHeldCall()` as it is: that one
checks that something does *not* happen.

- [ ] **Step 5: Verify on a quiet machine.**
Run: `swift test --filter "WindowFlyout|RevocationTests"` — expected: all pass.

- [ ] **Step 6: Verify under load.** Run Task 8 Step 5's three commands again, exactly.
Expected: five `run N exit 0` lines, no counts. If a run fails, report its
`rg -n -B2 -A8 "Fatal|recorded an issue" /tmp/nexus-load-N.txt` output and stop. Do NOT fix
other tests that fail: report them.

- [ ] **Step 7:** `make lint` — expected: exits 0, no warnings.

- [ ] **Step 8: Commit.**
```bash
git add Tests/NexusUITests/WaitUntil.swift Tests/NexusUITests/WindowFlyoutTests.swift Tests/NexusUITests/DisplayAndRecoveryTests.swift docs/plans/2026-10-27-review-baseline-fixes.md
git commit -m "test: permission tests wait for the event instead of a fixed sleep"
```
