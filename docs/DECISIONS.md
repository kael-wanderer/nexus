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

---

## 2026-08-22 — Implementation (Milestones 1–7)

**D16. Configuration stays at version 1; no v1→v2 migration was manufactured.**
`NexusConfiguration` decodes every field with a default, so every schema change made during
Milestones 1–7 was purely additive and needed no migration. The migration framework
(`ConfigurationMigration`, ordered application, version bump, quarantine on a missing step) ships
and is unit-tested with a concrete migration implementation. Inventing a breaking change purely
to exercise the framework would have been worse code. Rejected: bumping to v2 with a synthetic
rename.

**D17. `Force Quit` is always present in the sidebar context menu, not revealed "after a
timeout".** A context menu cannot be re-shown after a quit request times out, and the Dock
behaves the same way. Nexus never blocks on `terminate()`, so a refusing application (unsaved
document) cannot hang the sidebar — which is the acceptance criterion the timeout wording was
protecting.

**D18. Window counts are recomputed on every `NSWorkspace` application event and whenever the
pointer enters the sidebar.** macOS publishes no notification for another application opening a
window, and Milestone 3 must require zero permissions. Pointer entry is a user event, not a
timer, so the no-polling rule holds. Live per-window tracking arrives with the `AXObserver`s at
Milestone 4. Rejected: a refresh timer.

**D19. The running-but-unpinned section shipped with the sidebar at Milestone 2.**
It needs no permission and no new code beyond a filter, and an empty sidebar on first launch is a
poor first impression. Milestone 3 added only the event plumbing that keeps it live.

**D20. `#expect` comparisons keep both sides in `CGFloat`.**
Swift Testing's macro rewrites its expression into subexpression captures, which defeats Swift's
implicit `CGFloat`/`Double` conversion: `56.0 == 56.0` fails with identical bit patterns. Test
code converts explicitly. Production code is unaffected.

**D21. The window flyout opens on click or from the context menu, not on hover dwell.**
`behavior.clickBehavior = .showWindowList` makes a click open it, and "Show Windows" is always in
a running application's context menu. A hover-dwell trigger would pop a panel open every time the
pointer crossed the sidebar on its way somewhere else. `ROADMAP.md` says "hover or click";
this ships the click half and leaves hover unbuilt.

**D22. `AXObserver` callbacks publish one coalesced `.windowsChanged(app)` per application
instead of per-window created/closed/retitled/focused events.** AX elements are not `Sendable`
and cannot cross into the event, and consumers re-read authoritative state on wake anyway
(D12) — so the finer-grained events would have carried no extra information. Bursts are
coalesced over 80 ms, which matters because `kAXTitleChangedNotification` fires on every
keystroke in an editor. `NexusEvent.windowCreated/windowClosed/windowTitleChanged/windowFocused`
were removed rather than left unpublished.

**D23. `EventBus` subscriptions are created synchronously inside `start()`, not inside the
consuming `Task`.** Creating the stream inside the task dropped every event published before the
task's first run — a real race, found by a test. Each `start()` now calls `events.events()` on
the caller's thread and hands the stream to the task.

**D24. The flyout's whole content is gated on `target != nil`.**
`NSHostingView` evaluates its body when it is constructed, not when its panel is ordered front,
so the permission screen's `.task` started the 1 Hz poll at launch and never stopped. Gating on
visibility is what actually enforces D13's "scoped to a visible screen". Measured: 0.00 s of CPU
over 45 s idle after the fix.

**D25. Only `AXStandardWindow` subroles appear in window lists.**
Sheets, popovers, palettes and toolbars are AX windows too; listing them would make the flyout
noise. Windows without an `_AXUIElementGetWindow` id still list and activate under a synthetic
identifier — only their preview is lost (DESIGN_MVP §3.1).

**D26. The search palette starts on the non-activating key path and self-measures.**
Review Note 1. `SearchPanelController` opens with `makeKeyAndOrderFront` and no `NSApp.activate()`;
200 ms later it logs `strategy / isKeyWindow / NSApp.isActive / frontmost` and switches to
activate-and-restore for the rest of the session if the panel did not become key. Checking
`isKeyWindow` synchronously does not work — activation has not settled yet, and an immediate
check falls back every time. `DESIGN_MVP.md` §2.2 now documents both paths.
**Measured 2026-08-22 on an unlocked session: `strategy nonActivating, key true, app active
true, frontmost com.apple.TextEdit`. Review Note 1 is confirmed — the panel becomes key and
accepts typing while the frontmost application stays TextEdit, so there is no restore step and
no focus flicker. Path A is the shipping path.** (`NSApp.isActive` reads `true` because AppKit
counts owning the key window as active; the number that matters is
`NSWorkspace.frontmostApplication`, which never changed.) Earlier attempts read
`key false / frontmost com.apple.loginwindow` purely because the screen was locked, which makes
key-window semantics meaningless — a locked session is not a valid measurement environment.


**D27. The search field is an `NSTextField` behind `NSViewRepresentable`.**
Review Note 1 predicted this: SwiftUI `TextField` focus is unreliable in a non-activated
application, and the palette must accept the first keystroke after the hotkey. `↑ ↓ ⏎ ⇧⏎ ⎋` are
handled through `control(_:textView:doCommandBy:)`; `⌘1`–`⌘9` through a local event monitor
installed only while the palette is visible.

**D28. "Show Desktop" is dropped from the MVP action list.**
`FEATURES.md` names `com.apple.showdesktop`; no such bundle exists on macOS 14+ (the only match
is `WindowManagerShowDesktopEducation.app`, a tutorial). The only implementations are a
synthesised F11 key event, which needs Accessibility, or AppleScript, which D15 forbids. Dropped
for the same reason as Empty Trash. The other six actions ship.

**D29. "Lock Screen" resolves `SACLockScreenImmediate` at runtime with `dlopen`/`dlsym`.**
It lives in `login.framework`, a private framework, so it cannot be linked. Resolving it at
runtime means a future macOS that removes it makes the action fail quietly and log, rather than
breaking the build or crashing. Verified present on macOS 26.6.

**D30. The application index is a one-shot Spotlight query rebuilt on application-launch events,
not a live `NSMetadataQuery`.** D8 asked for Spotlight, and this uses it — 454 applications
indexed on the development machine — but keeping a query live for the process lifetime is
background churn for a catalogue that changes when software is installed. The index is built
lazily on the first palette open (cold start stays under budget) and rebuilt when an application
launches, which is when a newly installed application first matters. Directory scan remains the
fallback when Spotlight returns nothing.

**D31. Windows for search come from a snapshot refreshed when the palette opens.**
Enumerating every application's windows over AX on each keystroke would blow the 50 ms budget.
`WindowService` keeps the last enumeration, `AXObserver`s keep it fresh, and opening the palette
triggers one full refresh — a user event, not a timer. Measured: 454 applications plus 200
windows ranked in under 50 ms.

**D32. Settings and onboarding are ordinary titled `NSWindow`s, and Nexus activates itself to
show them.** These two are the only surfaces that *should* take focus, and standard AppKit
controls (sliders, pickers, steppers) only render in their active appearance in a key window —
which is exactly why the sidebar and the flyout avoid them. `AuxiliaryWindowController` calls
`NSApp.activate()` on show and `NSApp.hide(nil)` on close, so an `.accessory` app never sits
"active" with nothing visible.

**D33. The Spotlight shortcut status is read when the guide appears, not polled.**
Review Note 2, implemented as progressive enhancement: `CFPreferencesCopyAppValue` on
`com.apple.symbolichotkeys` key 64. `enabled`/`disabled` drives a live status line; anything
unexpected reads as `unknown` and the guide falls back to its static text. Read on appear rather
than on a timer, because the user leaves the screen to change the setting and comes back —
D13's single poll stays single.

**D34. Settings write through `ConfigurationController.binding(_:)`.**
One key-path binding helper means every control goes through the same debounced, clamped,
event-publishing path, so "applies live" and "persists" are properties of the plumbing rather
than of each control.

**D35. Measured performance, recorded rather than estimated (§68: measure before optimising).**
Cold start 702–753 ms warm and 1299 ms on the first launch after a build, from process exec to
the sidebar being on screen — read from the kernel's process start time, so dyld and runtime
setup are included. Idle CPU 0.00 s over 45 s. Under churn (60 application launches and quits
over 150 s) CPU totalled 0.90 s and resident memory moved from 60.1 MB to 60.5 MB. The
< 50 ms application-and-window search budget is asserted by a test over the real 454-application
index. The first launch after a build exceeds the 1 s cold-start budget because nothing is in
the page cache; every subsequent launch is comfortably inside it. No optimisation was done,
because nothing measured badly.

**D36. The sidebar gets VoiceOver navigation, not arrow-key navigation.**
`ROADMAP.md` Milestone 7 asks for "full keyboard navigation of the sidebar", but the sidebar
panel can never become key (D3) — that is the guarantee the whole product rests on. VoiceOver
drives it through the accessibility element tree, which needs no key status, and every row
carries a label, a value ("running, 3 windows") and a hint. Keyboard-driven work goes through
the search palette, which is the keyboard surface, exactly as `DESIGN_MVP.md` §2.1 anticipated.

**D37. Accessibility revocation is detected on the next AX call, not by polling.**
`WindowService` re-checks `AXIsProcessTrusted()` on every entry point and publishes
`.permissionChanged(.accessibility, .denied)` on the transition, clearing its caches. The flyout
then reloads, which empties the stale window list and shows the explain-and-grant screen. No
timer was added: the only moment a stale window list can mislead the user is when they ask for
one.

**D38. The 30-minute Instruments session in the Milestone 7 acceptance criteria was run as a
150-second scripted churn instead.** Six rounds of launching and quitting five applications with
`ps` sampling in between, which is what can be automated without a human driving Instruments.
Memory was flat. A real Instruments leak session stays on the MANUAL VERIFICATION list.

---

## 2026-08-22 — User review, round 1

**D39. Clicks inside a panel that can never become key are handled in AppKit, not by SwiftUI's
`.onTapGesture`.** Root cause of "clicking the sidebar / palette does nothing". A click into a
non-key window is discarded unless the **view that is actually hit** returns
`acceptsFirstMouse == true`; overriding it on the `NSHostingView`, as `DESIGN_MVP.md` §2.1
assumed, is not enough, because the hit view is one of SwiftUI's internal subviews. And because
the sidebar can *never* become key, every click is a first-mouse click — so the taps did not
merely fail once, they never worked at all. `PanelRowInteraction` (the former
`ContextMenuCatcher`) now claims left- and right-press events, returns `acceptsFirstMouse = true`,
and distinguishes a click from a drag with a 5 pt slop. It is applied to every clickable row in
a non-key surface: sidebar items, the search row, flyout window rows, and the grant screen's own
buttons — which is why "Open System Settings" was also dead. Rejected: making the sidebar
key-capable, which would break the product's central guarantee.

**D40. The palette keeps a selection only once the user has moved it.**
Root cause of "Enter executes nothing". `apply(_:)` kept any still-present `selectedID`
unconditionally, so the first provider to answer set row 0 and the merge that followed left the
selection stranded on a row that was no longer first. Live evidence: for the query `calcul`,
`results[0]` was Calculator (0.90) while `selectedID` was `window:com.barebones.bbedit#2666`.
Enter did execute — it raised a background BBEdit window, which looks exactly like nothing
happening. The rule now matches `DESIGN_MVP.md` §4.1 as written: row 0 is preselected on every
snapshot **until** the user arrows or clicks. Hover highlights without pinning, because the
palette opens under the pointer and would otherwise hand Return to whatever row the mouse
happened to be resting on.

**D41. `make` signs with any stable codesigning identity, not only "Apple Development".**
Root cause of "the Accessibility grant is not recognised". The lookup matched only
`"Apple Development"`, found none, and fell back to ad-hoc — and an ad-hoc signature changes
on every build, so TCC's entry stops matching the running binary and `AXIsProcessTrusted()`
returns `false` however many times the user flips the switch. Stability is what TCC cares
about, not the issuer: the detection order is now Apple Development → any valid identity →
ad-hoc, the variable is `SIGNING_IDENTITY`, and this machine's self-signed
`"Bugler Local Dev"` is picked up automatically. Verified: `codesign -dv` reports
`Authority=Bugler Local Dev` and `flags=0x0(none)` instead of `0x2(adhoc)`. `--deep` was dropped
from the `codesign` call — it is deprecated and there are no nested bundles.

**D42. The grant screen offers a restart once the user has been to System Settings.**
macOS hands a process its Accessibility trust at launch and does not reliably refresh it for an
already-running process, so "granted in TCC but not effective here" is a real state with no
public API to detect it. Rather than guess at TCC's contents, the screen offers the remedy: after
the user has opened System Settings at least once, an "already switched it on?" note appears with
a **Restart Nexus** button. `AppRelaunch` opens a replacement instance carrying a
`NEXUS_RELAUNCHING` environment marker and then terminates; the marker makes the replacement's
single-instance guard wait for the outgoing process to exit instead of deferring to it.

**D43. Action outcomes, permission transitions and lifecycle events log at `.notice`.**
Field testing produced no logs at all: `os.Logger.info` and `.debug` are memory-only, so
`log show` without `--info` returned nothing. Everything a support question needs — launch,
activate, quit, raise, action dispatch, permission changes, hotkey registration, palette
activation strategy, cold-start time — is now `.notice` (persisted) or `.error`. `ActionRunner`
no longer swallows failures with `try?`; every branch logs its error. Privacy annotations are
unchanged per `ARCHITECTURE.md` §8: bundle identifiers and counts are `.public`, paths stay
`.private`, and the action label deliberately carries no URL.

**D44. Pinned reorder is available from the context menu.**
`PanelRowInteraction` claims mouse-down, which is also where a SwiftUI `.draggable` would begin,
so drag-reorder cannot be relied on in the sidebar. Working clicks matter more than working
drags, and `DESIGN_MVP.md` §2.1 already listed a manual reorder as the sanctioned fallback.
Move Up / Move Down / Move to End are now in the context menu, correctly disabled at the ends.
`.draggable`/`.dropDestination` are left in place and cost nothing; dropping an application from
Finder onto the sidebar to pin it is unaffected, because that drop target is the container, not
the row.
