# Decisions — Foundation

Build, configuration, the event bus, logging, measurement — the decisions everything else stands on.

Part of the decision log; the index, and the rule these follow, are in
[`../decisions.md`](../decisions.md). Numbers are global and never reused, so the gaps
here are entries that live in another file, and the date each was made is in `git log`.

## D1. Build system: SwiftPM package + `Makefile`, no checked-in `.xcodeproj`.
`swift build` / `swift test` run headlessly, which the milestone-gated workflow needs, and a
`.pbxproj` is merge-hostile. §111.4 leaves the format open. Cost: no SwiftUI previews, no
XCUITest until an Xcode wrapper target is added (Milestone 7, only if §67's critical-flow tests
earn it).

## D2. Bundle identifier `com.congbui.nexus`, fixed permanently.
TCC keys permission grants to signature + bundle identifier; changing either resets every grant
(§111.3).

## D9. Configuration lives in `UserDefaults` as versioned JSON; migrations operate on the JSON
dictionary.
Native, atomic, `defaults`-inspectable. Migrating dictionaries rather than typed
structs means obsolete versions of the model never have to be kept in the source tree.

## D10. A newer-versioned configuration is left on disk untouched and defaults are used in
memory.
A downgrade must never destroy a newer Nexus's settings. Corrupt data is copied aside
before falling back.

## D12. `EventBus` is a ~40-line typed multicast over `AsyncStream`.
`NotificationCenter` is untyped and awkward under strict concurrency; per-service streams alone
would force every consumer to know every producer. Slow subscribers drop events
(`.bufferingNewest(64)`) and re-read authoritative state on wake, so a drop costs a refresh,
never correctness.

## D15. No shell execution, AppleScript or `osascript` in the MVP.
Those need Automation permission and belong to the automation engine (§46, out of scope).
"Empty Trash" is dropped from the action list for the same reason plus its destructive
confirmation UX.

---

## D16. Configuration stays at version 1; no v1→v2 migration was manufactured.
`NexusConfiguration` decodes every field with a default, so every schema change made during
Milestones 1–7 was purely additive and needed no migration. The migration framework
(`ConfigurationMigration`, ordered application, version bump, quarantine on a missing step) ships
and is unit-tested with a concrete migration implementation. Inventing a breaking change purely
to exercise the framework would have been worse code. Rejected: bumping to v2 with a synthetic
rename.

## D20. `#expect` comparisons keep both sides in `CGFloat`.
Swift Testing's macro rewrites its expression into subexpression captures, which defeats Swift's
implicit `CGFloat`/`Double` conversion: `56.0 == 56.0` fails with identical bit patterns. Test
code converts explicitly. Production code is unaffected.

## D23. `EventBus` subscriptions are created synchronously inside `start()`, not inside the
consuming `Task`.
Creating the stream inside the task dropped every event published before the
task's first run — a real race, found by a test. Each `start()` now calls `events.events()` on
the caller's thread and hands the stream to the task.

## D34. Settings write through `ConfigurationController.binding(_:)`.
One key-path binding helper means every control goes through the same debounced, clamped,
event-publishing path, so "applies live" and "persists" are properties of the plumbing rather
than of each control.

## D35. Measured performance, recorded rather than estimated (§68: measure before optimising).
Cold start 702–753 ms warm and 1299 ms on the first launch after a build, from process exec to
the sidebar being on screen — read from the kernel's process start time, so dyld and runtime
setup are included. Idle CPU 0.00 s over 45 s. Under churn (60 application launches and quits
over 150 s) CPU totalled 0.90 s and resident memory moved from 60.1 MB to 60.5 MB. The
< 50 ms application-and-window search budget is asserted by a test over the real 454-application
index. The first launch after a build exceeds the 1 s cold-start budget because nothing is in
the page cache; every subsequent launch is comfortably inside it. No optimisation was done,
because nothing measured badly.

## D38. The 30-minute Instruments session in the Milestone 7 acceptance criteria was run as a
150-second scripted churn instead.
Six rounds of launching and quitting five applications with
`ps` sampling in between, which is what can be automated without a human driving Instruments.
Memory was flat. A real Instruments leak session stays on the MANUAL VERIFICATION list.

---

## D41. `make` signs with any stable codesigning identity, not only "Apple Development".
Root cause of "the Accessibility grant is not recognised". The lookup matched only
`"Apple Development"`, found none, and fell back to ad-hoc — and an ad-hoc signature changes
on every build, so TCC's entry stops matching the running binary and `AXIsProcessTrusted()`
returns `false` however many times the user flips the switch. Stability is what TCC cares
about, not the issuer: the detection order is now Apple Development → any valid identity →
ad-hoc, the variable is `SIGNING_IDENTITY`, and this machine's self-signed
`"Bugler Local Dev"` is picked up automatically. Verified: `codesign -dv` reports
`Authority=Bugler Local Dev` and `flags=0x0(none)` instead of `0x2(adhoc)`. `--deep` was dropped
from the `codesign` call — it is deprecated and there are no nested bundles.

## D43. Action outcomes, permission transitions and lifecycle events log at `.notice`.
Field testing produced no logs at all: `os.Logger.info` and `.debug` are memory-only, so
`log show` without `--info` returned nothing. Everything a support question needs — launch,
activate, quit, raise, action dispatch, permission changes, hotkey registration, palette
activation strategy, cold-start time — is now `.notice` (persisted) or `.error`. `ActionRunner`
no longer swallows failures with `try?`; every branch logs its error. Privacy annotations are
unchanged per `ARCHITECTURE.md` §8: bundle identifiers and counts are `.public`, paths stay
`.private`, and the action label deliberately carries no URL.

## D45. "The sidebar only shows Calculator" was contaminated test state, not a defect.
The stored configuration read `showRunningApplications: false` with
`pinnedApplications: ["com.apple.calculator"]` and `onboarding.hasCompleted: true` — values a
round-1 debugging script wrote directly into the real `com.congbui.nexus` defaults domain and
never cleaned up. The sidebar was rendering that configuration correctly. Proved by clearing it
and relaunching against 25 running applications: the panel measured 1469 pt, exactly the height
`SidebarLayout` predicts for 25 running rows plus the search row, so initial population from
`NSWorkspace.shared.runningApplications` was never broken. Every hypothesis in the report
(missing initial snapshot, a D23-style dropped-event race, a wrong `activationPolicy` filter,
accumulate-only-from-launch-events) is disproved by that measurement and by the new
`SidebarPopulationTests`. **Lesson recorded because the fault was in the process, not the code:
never write to the product's real defaults domain from a test script.** `make reset-config` now
exists so this state is one command to undo.

## D47. "Persisted logging still produces nothing" is a shell collision, not a logging fault.
`log` is a **shell builtin** in this environment and shadows `/usr/bin/log`; the user's
`log show --predicate …` never reached the real binary, failing with
`(eval):log:8: too many arguments`. Reproduced exactly. With the absolute path, plain
`log show` (no `--info`, no `--debug`) returns the full trail, confirming that D43's move to
`.notice` works. `make logs` now wraps the absolute path so nobody has to know this.

## D48. Every remaining `.info` call was raised to `.notice`.
D43 raised the action and permission paths but left eight state-change lines behind — monitor
start, onboarding completion, pin/unpin, Spotlight fallback, display fallback, configuration
fallback. `os.Logger.info` is memory-only, so those were invisible in exactly the situation they
are written for. There are now no `.info` calls in the source tree. Added a
`Sidebar rows: N pinned, M running (showRunningApplications=…)` line on every layout change,
which is the single line that would have answered this round's report immediately.

## D67. Every configuration section decodes tolerantly, not just the root.
A synthesised `Codable` treats a missing key as an error, so adding one field to
`AppearanceConfiguration` made the *whole section* fail to decode and fall back to defaults — an
upgrade would silently reset the user's width, position and opacity. Caught by the existing
clamping test the moment `startMenuCorner` was added, which means M10's `hoverPreview` had already
shipped the same trap for `BehaviorConfiguration`. `General`, `Appearance`, `Behavior` and
`Search` now decode field by field with `decodeIfPresent`, and a regression test loads a payload
written before those fields existed.

## D86. Nexus installs into /Applications, and says so when it has not.
Launch at login is `SMAppService.mainApp`, which registers *the bundle where it stands*. Registered
from `build/Nexus.app` — where every developer and, until now, the only user ran it from — the login
item points into a build directory that `make clean` deletes, and macOS then launches nothing at
login with no error anywhere the user can see.

`make install` copies the signed bundle to `/Applications` with `ditto`, so the signature is
untouched and the Accessibility and Screen Recording grants survive the move; the running instance is
stopped first, because the single-instance guard would otherwise hand the launch straight back to the
copy in `build/`. It refuses outright to install an ad-hoc build: a signature that changes on every
rebuild is exactly what an installed application must not have.

The toggle in Settings carries the other half. When the running bundle is not in either Applications
folder, it says so under the switch rather than registering a path that will not survive. The check
is the parent directory against `FileManager.urls(for: .applicationDirectory, in:)` for both domains,
with symlinks resolved — `/Applications/Utilities/Nexus.app` is not an install location either,
because a login item that survives someone tidying their Applications folder into subfolders is a
claim we cannot keep.
