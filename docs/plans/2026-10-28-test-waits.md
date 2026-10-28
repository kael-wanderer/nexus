# Test waits: replace guessed sleeps with waits — implementation plan

> **For agentic workers:** execute tasks in order and check every box. If a quoted anchor differs from the checkout, stop and report; do not improvise. Scope is test code only: no file under `Sources/` changes.

**Goal:** Finish the work started in `fix/review-baseline`. A UI test that sleeps for a fixed time and then checks for an effect that an event *will* produce fails when the machine is busy. Every such sleep becomes a `waitUntil`. A sleep that shows something does *not* happen stays, because waiting cannot prove absence.

**Tech stack:** Swift 6, SwiftPM, Swift Testing. Work from `/Users/cong.bui/Kael/19-AppBuild/Nexus`. Comments use British spelling. `make lint` must stay at zero warnings. Do not touch `docs/reviews/`, `Sources/`, or `Tests/NexusCoreTests/` (core tests have their own helpers and no reported flakes).

**Rule used to classify each sleep (already applied below; do not reclassify):**

- *Effect expected* → `try await waitUntil { condition }`, keep the following `#expect` lines unchanged.
- *Nothing should happen* (`isEmpty`, `== 0`, `== nil` after a cancel, unchanged bytes) → keep the sleep.
- *Fake delays* inside a fake provider or service → keep.

---

### Task 0: Branch

- [ ] `git switch main && git switch -c test/wait-for-effects`
- [ ] `swift build --build-tests 2>&1 | tail -3` succeeds before any edit.

### Task 1: One wait helper that accepts async conditions

`Tests/NexusUITests/WaitUntil.swift` takes a synchronous condition. `Tests/NexusUITests/WindowFlyoutTests.swift:96-104` defines a second helper, `until`, that takes an async one, with no timeout and no `throws`. Merge them into `waitUntil`.

- [ ] In `Tests/NexusUITests/WaitUntil.swift`, replace the function (keep the doc comment above it) with:

```swift
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while await !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
}
```

- [ ] In `Tests/NexusUITests/WindowFlyoutTests.swift`, delete the `until` function and its two-line doc comment (anchor: `/// Polls until \`condition\` holds, up to two seconds. Replaces a fixed sleep in tests that wait on`).
- [ ] Replace every `await until {` in `Tests/NexusUITests/` with `try await waitUntil {`. Current callers (check with `rg -n 'await until \{' Tests/NexusUITests/`):
  - `WindowFlyoutTests.swift:182` (in `granted()`, already `throws`)
  - `WindowFlyoutTests.swift:320` (in `newWindowHidesFlyout()`)
  - `SidebarPolishTests.swift:228` (in `dropsAtPosition()`)
  - `SidebarPolishTests.swift:395` (in `opensOnHover()`)
  - `BarZonesTests.swift:402` (in `opensOnHover()`)
  - `SearchScopeUITests.swift:51` and `:54` (in `scopeNarrowsResults()`)
- [ ] Each enclosing test function that is `async` but not `async throws` becomes `async throws`: `newWindowHidesFlyout`, `dropsAtPosition`, both `opensOnHover`, `scopeNarrowsResults`.
- [ ] Fold the two hand-written poll loops into the helper:
  - `SidebarPopulationTests.swift:46-48`: replace the `for _ in 0..<200 where model.running.isEmpty { … }` loop with `try await waitUntil { !model.running.isEmpty }`.
  - `OnboardingTests.swift:28-34`: make the body of `waitForCandidates` a single line, `try? await waitUntil { model.candidates.count >= expected }`. Keep its signature and doc comment; its callers do not change. (`try?` is deliberate: the caller's `#expect` reports the failure.)
- [ ] `rg -n 'func until\b|await until \{' Tests/NexusUITests/` prints nothing.
- [ ] `swift build --build-tests 2>&1 | rg -i 'warning|error'` prints nothing.
- [ ] Commit: `test: merge the two UI test wait helpers`.

### Task 2: Convert the sleeps that wait for an effect

Edit only these lines. Each replacement removes the `Task.sleep` line and puts the shown line in its place.

| File:line | Test | Replace the sleep with |
|---|---|---|
| `SidebarViewModelTests.swift:69` | `clickBehaviour` | the block below |
| `SidebarViewModelTests.swift:347` | `hoverOpensFlyout` (make it `async throws`) | `try await waitUntil { shown == ["a"] }` |
| `WindowFlyoutTests.swift:209` | `liveUpdate` | `try await waitUntil { model.windows.map(\.identity.number) == [1] }` |
| `WindowFlyoutTests.swift:267` | `ownerTerminated` | `try await waitUntil { model.target == nil }` |
| `SearchSelectionTests.swift:76` | first test in the suite | `try await waitUntil { model.results.first?.category == .application }` |
| `SearchSelectionTests.swift:97` | `try await Task.sleep(for: .milliseconds(200))` after `model.query = "on"` | `try await waitUntil { model.selectedID == model.results.first?.id }` |
| `SearchSelectionTests.swift:138` | `hoverDoesNotPinSelection`, the 30 ms sleep | `try await waitUntil { !model.results.isEmpty }` |
| `SearchSelectionTests.swift:143` | `hoverDoesNotPinSelection`, the 400 ms sleep | `try await waitUntil { model.results.first?.category == .application }` |
| `SearchSelectionTests.swift:156` | `clickExecutesTheClickedRow` | `try await waitForResults(model, count: 2)` |

Block for `SidebarViewModelTests.swift:69` (an `&&` cannot hold an `await` on its right side, so read both first):

```swift
        try await waitUntil {
            let activated = await service.activated
            let launched = await service.launched
            return activated == ["com.apple.Safari"] && launched == ["com.apple.Terminal"]
        }
```

**Keep these sleeps exactly as they are** (each shows that something does not happen, or is a fake's delay):

- `SidebarViewModelTests.swift:367, 407, 421`
- `DisplayAndRecoveryTests.swift:168, 195`
- `SidebarPolishTests.swift:272, 408, 415`
- `BarZonesTests.swift:409, 421`
- `SearchSelectionTests.swift:16` (fake provider delay) and `:170` (no results)
- `WaitUntil.swift` (the poll interval itself)

- [ ] Apply the nine replacements.
- [ ] `rg -c 'Task\.sleep' Tests/NexusUITests/` totals **13**: the 12 kept sleeps listed above plus the one in `WaitUntil.swift` (it was 25 before Task 1). If the total differs, stop and report which file differs.
- [ ] `swift build --build-tests 2>&1 | rg -i 'warning|error'` prints nothing.
- [ ] Commit: `test: wait for effects instead of guessing a delay`.

### Task 3: Verify under load

Idle runs prove nothing here: these tests only failed with every core busy.

- [ ] `make lint` reports zero warnings.
- [ ] `swift test 2>&1 | tail -5`: all tests pass (baseline 309 UI + 213 core).
- [ ] Load every core, run the suite five times, then always stop the load:

```bash
for n in $(seq 1 $(sysctl -n hw.ncpu)); do (yes > /dev/null &); done
for i in 1 2 3 4 5; do swift test > /tmp/nexus-load-$i.log 2>&1; echo "run $i exit $?"; done
pkill -x yes
```

- [ ] All five runs exit 0. If a run fails, find the test with `rg -n '✘|failed' /tmp/nexus-load-<n>.log`; for a crash read the newest `~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-*.ips`. Report the test name and line; do not add sleeps or longer timeouts to make it pass.
- [ ] `pgrep -x yes` prints nothing.
- [ ] Commit nothing further. Do not merge or push; report back with the five exit codes, the test counts and the final `rg -c` total.
