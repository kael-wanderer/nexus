# Decisions

Ambiguity calls made during implementation, per the §32 rule: pick the simplest native macOS
option that preserves extensibility, record it, continue. Newest last.

Format: **date — decision — reason — alternative rejected.**

---

## 2026-08-22 — Phase 1 design

**D1. Build system: SwiftPM package + `Makefile`, no checked-in `.xcodeproj`.**
`swift build` / `swift test` run headlessly, which the milestone-gated workflow needs, and a
`.pbxproj` is merge-hostile. §111.4 leaves the format open. Cost: no SwiftUI previews, no
XCUITest until an Xcode wrapper target is added (Milestone 7, only if §67's critical-flow tests
earn it).

**D2. Bundle identifier `com.congbui.nexus`, fixed permanently.**
TCC keys permission grants to signature + bundle identifier; changing either resets every grant
(§111.3).

**D3. Sidebar panel can never become key; the search palette activates the app deliberately.**
The two panels have opposite focus requirements, so they get opposite designs rather than one
shared abstraction. Details in `docs/DESIGN_MVP.md` §2.

**D4. Auto-hide reveal uses a 2 pt transparent edge-trigger panel with a tracking area.**
Event-driven and permission-free. Rejected `NSEvent.addGlobalMonitorForEvents(.mouseMoved)`:
wakes the process on every mouse move for a feature that fires a few times a minute.

**D5. Window counts come from `CGWindowListCopyWindowInfo`, titles from the AX API.**
Counts need no permission, titles do. Splitting the sources is what keeps Milestone 3
permission-free (§111.2).

**D6. `SearchResult` carries a `NexusActionDescriptor` value, not a closure.**
Keeps results `Sendable`, comparable and testable without executing side effects, and gives the
§81 action model a place to grow.

**D7. Debounce is per provider (file 120 ms, everything else 0 ms), not global.**
A global debounce would spend the entire 50 ms budget waiting for data already in memory.

**D8. The application index is an `NSMetadataQuery`, not a directory scan.**
Spotlight already indexes every application bundle anywhere on disk and pushes live updates —
no `FSEvents` watcher, no refresh timer. Directory scan is the fallback when Spotlight is
disabled.

**D9. Configuration lives in `UserDefaults` as versioned JSON; migrations operate on the JSON
dictionary.** Native, atomic, `defaults`-inspectable. Migrating dictionaries rather than typed
structs means obsolete versions of the model never have to be kept in the source tree.

**D10. A newer-versioned configuration is left on disk untouched and defaults are used in
memory.** A downgrade must never destroy a newer Nexus's settings. Corrupt data is copied aside
before falling back.

**D11. Displays are identified by `CGDisplayCreateUUIDFromDisplayID`, not `CGDirectDisplayID`.**
Display IDs change across disconnect/reconnect; UUIDs do not.

**D12. `EventBus` is a ~40-line typed multicast over `AsyncStream`.**
`NotificationCenter` is untyped and awkward under strict concurrency; per-service streams alone
would force every consumer to know every producer. Slow subscribers drop events
(`.bufferingNewest(64)`) and re-read authoritative state on wake, so a drop costs a refresh,
never correctness.

**D13. Exactly one poll exists in the app: permission status at 1 Hz while a permission screen
is visible.** macOS publishes no TCC change notification and §111.6 requires a live checkmark.
Scoped to a visible screen and cancelled on dismiss.

**D14. Nexus never modifies the user's Dock settings.**
Silently changing a system setting is the intrusiveness §4 rules out. The README tells users how
to auto-hide the Dock themselves.

**D15. No shell execution, AppleScript or `osascript` in the MVP.**
Those need Automation permission and belong to the automation engine (§46, out of scope).
"Empty Trash" is dropped from the action list for the same reason plus its destructive
confirmation UX.
