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
shared abstraction. Details in `docs/design/mvp.md` §2.

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
identifier — only their preview is lost (design/mvp.md §3.1).

**D26. The search palette starts on the non-activating key path and self-measures.**
Review Note 1. `SearchPanelController` opens with `makeKeyAndOrderFront` and no `NSApp.activate()`;
200 ms later it logs `strategy / isKeyWindow / NSApp.isActive / frontmost` and switches to
activate-and-restore for the rest of the session if the panel did not become key. Checking
`isKeyWindow` synchronously does not work — activation has not settled yet, and an immediate
check falls back every time. `design/mvp.md` §2.2 now documents both paths.
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
the search palette, which is the keyboard surface, exactly as `design/mvp.md` §2.1 anticipated.

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
`acceptsFirstMouse == true`; overriding it on the `NSHostingView`, as `design/mvp.md` §2.1
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
happening. The rule now matches `design/mvp.md` §4.1 as written: row 0 is preselected on every
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
drags, and `design/mvp.md` §2.1 already listed a manual reorder as the sanctioned fallback.
Move Up / Move Down / Move to End are now in the context menu, correctly disabled at the ends.
`.draggable`/`.dropDestination` are left in place and cost nothing; dropping an application from
Finder onto the sidebar to pin it is unaffected, because that drop target is the container, not
the row.

---

## 2026-08-22 — User review, round 2

**D45. "The sidebar only shows Calculator" was contaminated test state, not a defect.**
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

**D46. The sidebar scrolls.** Clearing the contaminated configuration immediately exposed a real
defect behind it: 25 running applications need 1469 pt on a screen with 1325 pt of usable
height. `SidebarLayout.frame` clamped the *panel* to the screen but nothing clamped the
*content*, so the last rows were simply cut off. The row stack now lives in a `ScrollView`.
Verified: the same 25 applications now produce a 1310 pt panel that fits, with the overflow
reachable by scrolling. `PanelRowInteraction` (D39) already ignores `.scrollWheel` events, so
scrolling passes through to SwiftUI untouched.

**D47. "Persisted logging still produces nothing" is a shell collision, not a logging fault.**
`log` is a **shell builtin** in this environment and shadows `/usr/bin/log`; the user's
`log show --predicate …` never reached the real binary, failing with
`(eval):log:8: too many arguments`. Reproduced exactly. With the absolute path, plain
`log show` (no `--info`, no `--debug`) returns the full trail, confirming that D43's move to
`.notice` works. `make logs` now wraps the absolute path so nobody has to know this.

**D48. Every remaining `.info` call was raised to `.notice`.**
D43 raised the action and permission paths but left eight state-change lines behind — monitor
start, onboarding completion, pin/unpin, Spotlight fallback, display fallback, configuration
fallback. `os.Logger.info` is memory-only, so those were invisible in exactly the situation they
are written for. There are now no `.info` calls in the source tree. Added a
`Sidebar rows: N pinned, M running (showRunningApplications=…)` line on every layout change,
which is the single line that would have answered this round's report immediately.

**D49. The frontmost application is seeded at monitor start.**
`ApplicationService.activeBundleIdentifier` was only ever set by
`didActivateApplicationNotification`, so on a fresh launch no sidebar row showed as active until
the user switched applications once. `ApplicationMonitor.start()` now seeds it from
`NSWorkspace.shared.frontmostApplication`.

**D50. `.main` resolves to the menu-bar display, not `NSScreen.main`.**
Caught live while verifying D46: on a two-display setup the sidebar jumped to the second
monitor (x = 2568) because the onboarding window had opened there. `NSScreen.main` is
documented as *"the screen containing the window with keyboard focus"*, so it follows Settings
or onboarding onto whichever monitor they land on and drags the sidebar along. `design/mvp.md`
§8 defines `.main` as "the display with the menu bar", which is `NSScreen.screens.first`.
Added `DisplayService.menuBarScreen` and routed `.main`, `.withMouse`'s fallback and the
disconnected-`.specific` fallback through it. Verified: sidebar stays at x = 8 with onboarding
open on the other display.

## 2026-08-23 — Milestone 8, Dock replacement

**D51. Dock Replacement Mode is `defaults` keys plus a Dock restart.**
`autohide`, `autohide-delay` (1000 s), `autohide-time-modifier` and `orientation`, written with
`CFPreferences` and followed by terminating `com.apple.dock` — `killall Dock` without a shell,
since `launchd` brings it straight back. Rejected `NSApplicationPresentationHideDock`:
presentation options apply only while the owning application is active, and Nexus is an
`LSUIElement` that never activates, so the Dock would reappear the moment focus moved. Nothing
here touches `Dock.app`, system files or SIP — replace the Dock experience, not the Dock system
component.

**D52. Amends D14 ("Nexus never modifies the user's Dock settings").**
It may, but only on explicit user action, only while running, and only after capturing a
snapshot in which every field is optional — a key that was never set is *deleted* on restore,
never written back as `false` or `0`. Dock-less exists only while Nexus runs: quitting restores,
launching re-applies, and a launch that finds `applied` set without `replacementEnabled` cleans
up after a run that was killed. That is also the uninstall story, since macOS gives an
application no uninstall hook. `⌥⌘D` is deliberately left alone as the escape hatch that needs
no Nexus at all.

**D53. Hover-expand is vertical-only.**
A horizontal bar growing taller on hover would shove every window on the screen. The toggle stays
in Settings and says so while the position is top or bottom, rather than silently doing nothing.

**D54. The Dock is parked on the edge Nexus is not using.**
Sharing an edge would put the Dock's hot zone under Nexus's own edge trigger, where every stray
mouse flick arms a 1000-second timer. The Dock has no top edge, so a top or bottom sidebar sends
it left rather than to the literal opposite.

## 2026-08-23 — Milestone 9, Trash row and drag reorder

**D55. The Trash row has no full/empty state.**
Reading `~/.Trash` needs Full Disk Access — `kTCCServiceSystemPolicyAllFiles` for
`com.congbui.nexus` is an explicit deny on this machine — and a failed read is indistinguishable
from an empty Trash. The first build drew "empty" over a Trash holding 42 items. One icon that
never claims to know beats an icon that is silently wrong whenever the grant is missing, and an
icon is not worth asking for access to every file on the disk.

**D56. Drag-to-reorder is an AppKit dragging session inside `PanelRowInteraction`, not SwiftUI.**
Supersedes D44's "reorder by context menu only". The sidebar panel can never become key, so the
row interaction has to claim every mouse-down for a plain click to work at all, which means
SwiftUI never sees a drag start — `.draggable` was dead code. `mouseDragged` past the same 5 pt
slop that already separates a click from a press starts an `NSDraggingSession` carrying a private
pasteboard type (`com.congbui.nexus.sidebar-row`), so a text drag from another application can
never reorder anything, and the source mask is `.move` only within Nexus. Dropping a running
application onto a pinned row pins it in that slot. The context-menu items stay: they are the
keyboard-reachable path.

**D57. Empty Trash goes through Finder and asks first.**
`tell application "Finder" to empty trash` keeps the "put back" bookkeeping and the locked-item
rules that a hand-rolled `FileManager` delete would skip. It needs Automation access for Finder,
requested on first use; a refusal leaves the Trash untouched and is logged. The confirmation
alert is the one modal in the sidebar — the action cannot be undone.

## 2026-08-23 — Milestone 9, Dock parity

**D58. Supersedes D55: the Trash row shows full vs empty again, counted with `stat`.**
`readdir` on `~/.Trash` needs Full Disk Access, which Nexus is denied — but `stat` is not gated,
and on APFS a directory's `st_nlink` is `2 + entry count`. Measured from inside Nexus:
`contentsOfDirectory` → `nil`, `stat(~/.Trash)` → `nlink=44` for 42 items, `stat` of a file that
does not exist → fails, so it is a real answer rather than a blanket yes. Finder's own
`.DS_Store` and `.localized` are subtracted by name: Finder recreates `.DS_Store` the moment the
Trash window opens, and counting it would leave the full icon showing over an empty Trash. The
icons are the ones macOS itself uses, from `CoreTypes.bundle`, which is not protected either.

**D59. A drag shows a preview order; the configuration is written once, on drop.**
The dragged row fades to 35 % and `SidebarViewModel` holds a transient `previewOrder` that the
rows are sorted by, so the others slide out of the way exactly as they do in the Dock. Rows are
keyed by bundle identifier, so SwiftUI animates the moves on its own. A drag that is cancelled or
dropped outside restores the stored order — writing on every `draggingUpdated` would leave a
reordered dock behind after an abandoned drag.

**D60. The window list lives in the context menu; the flyout becomes "Show All Windows".**
Reaching an application's second window took right-click → Show Windows → flyout, where the Dock
takes one step. The menu now opens with the windows, frontmost ticked. `NSMenu` is built
synchronously and AX calls are not, so the titles come from a cache warmed when the pointer enters
the row; a row with nothing cached shows no window section rather than blocking. Without
Accessibility there is no section at all, which is the same split as D5 — counts are
permission-free, titles are not.

**D61. Window-count badges come from the Accessibility list, and are hidden without it.**
`CGWindowListCopyWindowInfo` is permission-free but counts the wrong things: measured here, Brave
showed 2 because its 387×64 "Find in page" bar is an ordinary layer-0 window, and Finder showed 2
where the menu listed 3. A badge that disagrees with the menu it sits next to is worse than no
badge, so counts now come from the same AX sweep that fills the menu — refreshed on the events
that already refresh counts, never on a timer — and the badge is not drawn at all while
Accessibility is missing. `WindowCounts.byProcess()` stays as the fallback that feeds nothing
visible; it is still what runs before the grant arrives.

**D62. A window with no AX subrole is not a window.**
The subrole filter accepted elements that answered nothing at all, which is exactly what Finder's
desktop is — hence "Finder" appearing as a third window in its own menu. The filter now requires
`AXStandardWindow`, which also keeps out `AXUnknown` panels like a browser's find bar.

**D59 (extended). Running applications get the drag preview too.**
The first cut previewed only pinned rows, so dragging a running application into the dock did
nothing until the drop — the exact failure the preview was added to fix. The preview order is now
a list of identifiers that may include an application that is not pinned yet; it leaves the
running section as the drag reaches the pinned one, and the drop is what pins it. A cancelled drag
puts it back.

**D63. The running section has a user order too, and a drag can cross the separator.**
Reordering only worked when the drop landed on a *pinned* row, so dragging one running
application onto another — the common case, "put Claude left of ChatGPT" — did nothing, which is
what "drag still does not work" meant. The running section now has its own stored order
(`runningApplicationOrder`), holding only the applications the user has actually moved; everything
else keeps its alphabetical place behind them, so the section does not shuffle itself when an
application launches. A drag lands in whichever section the row under the pointer belongs to,
which makes dragging across the separator pin or unpin — the same gesture the Dock uses.

## 2026-08-23 — Milestone 10, hover previews

**D64. Hover opens the flyout after a delay; switching rows while one is open is instant.**
Without the delay, sweeping the length of the bar opens and closes a dozen flyouts. Paying it
again for every row once one is already open is what makes hover docks feel sticky, so the timer
applies to opening, not to switching. The timer is cancelled the moment the pointer leaves the
row, and the flyout's existing 400 ms grace period is what lets the pointer travel from the row
to the flyout without it vanishing on the way.

**D65. A thumbnail arriving has to re-measure the flyout.**
Previews are captured after the flyout is already on screen, and the panel's frame is computed
from the hosting view's fitting size at the moment it opens. Storing an image therefore grew the
content inside a panel that kept its old frame: the thumbnails were captured, cached and drawn
entirely outside the visible bounds. `requestPreview` now calls `onContentChange` on arrival.
Found live — the logs said `Preview for window 3246: image` while the flyout showed titles only.

**D66. The preview service's failure paths log at `.notice`, not `.debug`.**
Same lesson as D48, in the one place it had survived: `os.Logger.debug` is memory-only, so "no
capturable window" and "preview unavailable" were invisible in exactly the situation they exist
for. The "window not found in `SCShareableContent`" branch had no logging at all.

## 2026-08-23 — Milestone 11, start menu

**D67. Every configuration section decodes tolerantly, not just the root.**
A synthesised `Codable` treats a missing key as an error, so adding one field to
`AppearanceConfiguration` made the *whole section* fail to decode and fall back to defaults — an
upgrade would silently reset the user's width, position and opacity. Caught by the existing
clamping test the moment `startMenuCorner` was added, which means M10's `hoverPreview` had already
shipped the same trap for `BehaviorConfiguration`. `General`, `Appearance`, `Behavior` and
`Search` now decode field by field with `decodeIfPresent`, and a regression test loads a payload
written before those fields existed.

**D68. The application index lists what a person can launch, not every bundle on the disk.**
Spotlight returns 454 bundles here; the start menu made that visible by showing
`ABAssistantService`, `AddressBookManager` and `Ainu Input Method` in a grid. Bundles declaring
`LSUIElement` or `LSBackgroundOnly`, helpers nested inside another `.app`, input methods and the
`CoreServices` scaffolding are filtered out — 132 remain. The palette gets the same filter, since
nobody was searching for those either.

**D69. The start menu's height is computed, not measured.**
A `LazyVGrid` inside a `ScrollView` reports no intrinsic height, so `fittingSize` measured the
field and the action row alone and the panel opened as a 106 pt sliver. The height comes from the
row count instead. The panel also has to be told when the index finishes building, since it opens
before the first build completes — `ApplicationIndex.onIndexed`.

**D70. Screen space is not reserved, windows are moved out of it.**
`NSScreen.visibleFrame` is the menu bar's and the Dock's to shrink; macOS offers no public API,
and no entitlement, that lets a third party reserve space. The private `CGSSetWorkspaceDockRect`
route would mean shipping against an unversioned SPI to fight the component Nexus has already
asked to hide. So Reserved Space watches for windows that overlap the bar and moves them off it,
through the Accessibility permission the window list already needs — pushed if they still fit,
resized only if they do not. The ceiling is honest and visible: a window can *open* over the bar
and be nudged a moment later, where the Dock's space was never available in the first place.

Two rules keep it from becoming a nuisance. Auto-hide turns it off entirely — a bar that comes and
goes cannot own space, and moving windows aside every time it appeared without ever putting them
back would be worse than doing nothing. And an application that puts its window straight back wins
after four attempts inside two seconds: the alternative is a fight that neither side ends.

Everything is compared in Accessibility coordinates, which grow downwards from the primary
display's top-left, unlike Cocoa's. `ScreenGeometry.flipped` is the only place that knows.

**D71. Grouping is asked for by resting on a row, not by dropping on it.**
The dock previews a reorder as the pointer moves (D59), which means the rows have already shifted
by the time a drag is over a row: "drop on Safari" and "drop between Safari and Terminal" are one
gesture, and only timing separates them. So a drag that rests on a row for 600 ms changes meaning
— the preview reverts, the dragged row leaves the bar, the target grows a ring, and letting go
merges the two. Dragging straight past a row reorders exactly as before. This is what iOS does,
and the dwell is what makes it discoverable without a modifier key nobody would find.

The name comes from `LSApplicationCategoryType`, which applications already declare and
LaunchServices already hands over with the icon: the category most members share, mapped to a word,
falling back to "Group". Renaming lives in the row's context menu behind an alert rather than in
the popover's header, because the popover can never become key and a text field nobody can type
into is worse than a menu item.

**D72. The dock repairs itself rather than trusting what it stored.**
`[DockEntry].repaired(capacity:)` runs on decode and after every edit: an over-full group keeps its
first members, an application listed twice keeps its first slot, a group of one becomes that
application, an empty group disappears. Capacity is a setting, so yesterday's nine-member group is
today's over-full one when it changes — enforcing it in one place means a hand-edited `defaults`
payload, a capacity change and a drag all end up in the same state. The stored v1 key
`pinnedApplications` is still written beside the entries so a downgrade finds its dock; nothing
reads it.

**D73. The bar has three zones, and only the middle one scrolls.**
Everything used to live in one `ScrollView` clamped to the screen, so past about two dozen rows
Trash and Search scrolled off the end and had to be hunted for. They are not rows like the others:
the launcher is a fixed head, Trash and Search (and later now-playing) are a fixed tail, and the
applications are a scrolling middle between them.

The middle gets a row budget per section — `appearance.pinnedLimit` (10) and
`appearance.runningLimit` (5) — resolved after the head and tail have taken their space, never
before. When the screen cannot hold both budgets, running keeps a floor of two rows and pinned
takes what is left: a dock full of pins must not hide the fact that other applications are open.
Overflow scrolls inside its own section, so nothing becomes unreachable, and both limits count a
group as one row — which is what makes groups worth having.

Limits rather than unbounded scrolling because scrolling to reach Search was the complaint. A bar
that grows without bound is a list; the overflow already has better answers than length — groups
for the applications you keep, the palette and the start menu for the ones you do not.

**D74. The bar's length is measured, not configured.**
Milestone 14 first shipped fixed budgets — ten pinned rows, five running — and they were wrong
within the hour: a bar with half the screen empty still scrolled to reach an application. The
number of rows an edge holds is not a preference, it is a measurement, and it differs per edge and
per display. A left or right bar has the screen's height to spend; a top or bottom bar has its
width. On 1920 × 1080 that is a different dock.

So capacity is computed — `slots = wholeRows(usable − head − tail − separators − padding)` — and the
two settings become ceilings on top of it, with **0** meaning "as many as fit" as the default. A row
that is switched off gives its slot back, which is what makes turning off the now-playing row worth
something. Scrolling begins where the screen ends, and not before.

Configuration version 3 exists only to reset the two values version 2 wrote: they were defaults
nobody chose, and keeping them would preserve the bug. A ceiling set deliberately after this point
is stored against the new meaning and survives.

One implementation note worth keeping: `rows(fitting:)` is called on every layout pass now, so it
has to survive being asked about an extent that is not a real screen. It was first written to trust
its input and trapped converting an infinite extent to `Int` — the model passes a large finite
extent before the first reframe, and the function caps its own answer.

**D75. What is playing comes from public sources, or not at all.**
`MediaRemote.framework` is what Control Center uses and would answer for every player at once. It
is private, and since macOS 15.4 it refuses callers without an Apple-internal entitlement: building
on it means shipping a feature that breaks on somebody's next software update. So Nexus asks three
public questions instead and shows exactly what they answer:

- **The track** comes from the distributed notifications Music and Spotify already post on every
  change (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`). Push, no
  permission, and both use the same keys, which is why one parser covers them.
- **The controls** are media keys — the system-defined events a keyboard's transport keys send.
  They reach whichever application owns playback, including a browser tab, and need no permission
  beyond the Accessibility grant Nexus already holds.
- **Whether anything is playing at all** is CoreAudio's per-process answer,
  `kAudioProcessPropertyIsRunningOutput`. The device-level version of that question was tried first
  and is useless: a browser holds the output device open for hours in silence, so the row never went
  away. Per process it is exact, and it names the process — which is what gives a browser tab an
  icon instead of a blank square.

What none of them give is a title for a player that publishes none, so the row shows controls and
the word "Playing" rather than scraping a window title and calling it a track. Artwork is the same
story: neither notification carries an image, so the row draws the player's own icon.

**D76. A player that publishes nothing is named by its window.**
D75 settled for controls and the word "Playing" for anything that is not Music or Spotify, on the
grounds that scraping a window title is guesswork. Using it made the answer obvious: an icon and
"Playing" is not what anyone means by *what is playing*, and it read as a duplicate of the
application's own row a few slots away.

The window title is not a guess for this purpose — it is what the player has already published to
every window list on the system. VLC names the file, a browser names the tab, and Nexus already
reads window titles through Accessibility for the flyout. So the title of the frontmost window of
the application CoreAudio says is making the sound becomes the track, after `MediaTitle` strips the
furniture: the media extension, the site's name (`… - YouTube`), and the application's own name.

It is still a heuristic and is treated as one. A window with nothing but the application's name in
it yields no title rather than a wrong one, published metadata always wins when it exists, and the
row is drawn as inset artwork with a waveform badge so it can never be confused with the
application's own icon.

**D77. The bar is six parts, and it says so.**
Launcher, pinned, running, now playing, Trash, Search. They were already six *kinds* of thing but
only three of them were separated, so the tail read as one undifferentiated clump — and with the
now-playing row in it, as a duplicate of the application it was playing. Each part is its own
section now, which means each gets the separator the layout already draws between sections, and the
zone maths counts one separator per fixed section rather than one for the whole tail.

**D78. "Nexus is my Dock" is one choice, not a toggle in a list.**
Running Nexus at the bottom of the screen with the macOS Dock still there gives you two docks, which
is nobody's intention. The Dock pane now opens with a two-way choice — *My Dock*, which hides the
system Dock while Nexus runs (D51/D52 do the work), or *A sidebar*, which leaves it alone. The
setting underneath is the same `dock.replacementEnabled`; what changed is that it now reads as the
decision it is, and says which of the two you are looking at.

**D79. Icons default to the size of a Dock tile.**
40 points was the default because it looked right in a narrow sidebar. Next to the macOS Dock it
looks like a downgrade: a dock replacement with smaller icons than the dock it replaces. The default
is 64 — a Dock tile at its own default — and configuration version 4 rewrites a stored 40, since
nobody chose it while it was the default. Any other size was set by hand and is kept.

**D80. Position is asked for, per player, and only while somebody is looking.**
`MediaRemote` would have reported position for every player at once, and it is closed (D75).
Nothing public reports how far into a video a browser tab is — so the timeline exists for the
players that ship a scripting dictionary (Music, Spotify, VLC) and is simply absent for the rest.
Absent, not faked: a row without a scrubber is honest, a scrubber that does not move is a bug that
looks like a feature.

That makes position the one thing in Nexus that is polled, since no notification carries it. The
poll is bounded by visibility rather than by frequency: once a second, and only while the player is
actually on screen — the expanded row or the open popover. It stops when the popover closes.
Seeking is a single write on release rather than one per pixel, because each one is an AppleScript
round trip and a player that receives forty of them stutters.

Two implementation notes. Spotify reports its duration in milliseconds where Music and VLC report
seconds, which is the kind of difference that silently turns a four-minute song into a
four-thousand-second one. And `NSAppleScript` is not thread-safe: run from an actor's own thread it
read nothing at all, and said nothing, because the failure path logged at `.debug` — the D66 lesson,
learned twice.

**D81. A click outside closes a popover, without waiting for the pointer to leave.**
The window flyout, the group popover and the media player all hid on a 400 ms grace period after the
pointer left, and on nothing else. A non-activating panel never loses key status — it never had any —
so there was no resign-key to hook, and clicking somewhere else left the popover sitting there. The
same global mouse monitor the palette needed (a click in another application never reaches a panel
that is not theirs) closes whichever popover is open, with the bar itself excluded: clicking the
media row is what opened it.

**D82. The wide media player spans four rows rather than becoming a section of its own.**
Two tiles with the scrubber hidden in a popover lasted an hour of real use. Four tiles is right on a
horizontal bar — but a section with its own pitch would have meant teaching `sectionExtent`, the
`slots` arithmetic and `rowCentre` to work in points instead of rows, which is the maths every other
part of the bar depends on.

So the wide player is one view sized to four rows' worth of extent. Everything stays row-based, the
change is a view and a row count, and the space it costs is visible in the same arithmetic as
everything else: four slots that the applications no longer get (D74). Which is also why it is a
setting — and why a narrow vertical bar ignores it, since four rows of height cannot hold a scrubber
worth dragging.

**D83. The player asks the player, and a paused player keeps its row.**
Two bugs with one cause: the row's existence and its play state were both inferred from CoreAudio
saying somebody was making sound.

- **Pausing deleted the player.** Pause stops the audio, the audio was the only evidence, so the row
  vanished — leaving nothing to press play on. A player that can be asked is now *asked*: while it
  still has something loaded, the row stays and shows a play button. A player that stops answering
  loses its row, and a browser tab — which cannot be asked anything — loses it when the sound stops,
  which is the best available answer.
- **The button always showed pause.** `isPlaying` was hard-coded true on the fallback path, so it
  never became a play button. Scriptable players report their own state; for the rest, making sound
  is still the only evidence there is.

Transport now goes through a script where the player has a dictionary, and falls back to a media key
where it does not. A media key is a request to whoever macOS thinks owns playback, which is not
always the player on the row and in VLC's case is often nobody at all — which is why the buttons
looked broken even when the click was landing. The keys stay for browser tabs, which no dictionary
covers.

**D84. The wide player's title goes above the scrubber, not instead of it.**
The row is 72 points tall and the scrubber with its clocks needs about 40, so the name is free.
`mediaContent` still chooses what the middle is *for* — a scrubber with a name over it, or the track
and artist alone — but the progress mode no longer hides what is playing.

**D85. The media player has no popover.**
It had one because for a while it *was* the player: two tiles in the bar could not hold a scrubber,
so the controls lived a hover away. The wide row (D82) put artwork, title, timeline and buttons on
the row itself, which made the popover a second copy of the same four things — and a hover between
you and the buttons you were looking at.

So it is gone, along with a panel, a 400 ms hover-out grace period, a re-layout on every track
change, a click monitor to dismiss it, and an anchor sentinel in `PanelController` for a row that is
not an application. Nothing opens when the pointer crosses the player now.

The one thing it held that the row cannot is a full, untruncated title, which is real on a compact
bar where the row is 64 points wide. That moved into the row's context menu as a disabled header —
right-click the player and it says what is playing. The group popover and the window flyout keep
their panels: those show things that genuinely do not fit in a bar.


**D86. Nexus installs into /Applications, and says so when it has not.**

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

**D87. Scopes are `⌃1`…`⌃6`, not `⌘1`…`⌘6`.**

`design/search-scope.md` asked for `⌘1`…`⌘6`. Those keys were already taken, and visibly so: every
result row in the palette draws its own `⌘N` badge and running the numbered result is how the
keyboard-first path works. A chord that means "run result 3" in one build and "search folders only"
in the next is worse than a chord nobody guesses first time.

So the digits move one modifier over: `⌘N` runs a result, `⌃N` picks a scope, and `⇥` / `⇧⇥` cycle
through the six for the hand that is already on the keyboard. `⇥` is handled in the field editor's
`doCommandBy` rather than a key monitor, because the palette has exactly one control and Tab would
otherwise walk focus out of it.

The chip that shows the current scope is also the menu that changes it, so the whole feature is
reachable with the mouse — and picking from that menu hands first responder back to the field
without selecting what is in it, or the next keystroke would replace the query the scope was chosen
for.

**D88. Every row carries its own accessibility action.**

The Definition of Done (§33) asks that Nexus be usable with the keyboard and by VoiceOver. The
labels were there from the start — every row has a label, a value carrying its state, and a hint —
and reading the bar worked. Pressing anything in it did not.

The cause is the same one that shapes half of Nexus: these panels can never become key, so nothing
in them is a SwiftUI `Button`. Rows are hit by `PanelRowInteraction` claiming the AppKit mouse-down,
and `.accessibilityAddTraits(.isButton)` only *says* button — it adds no action, so `AXPress` from
VoiceOver found nothing to perform and returned success having done nothing. Verified by pressing
the start-menu row through the Accessibility API: `AXPress` reported success and no menu opened.

So each row now adds `.accessibilityAction` next to its traits, doing exactly what its click does.
It has to live at the call site: an action added inside the `nexusRow` modifier is discarded by the
`.accessibilityElement(children: .ignore)` that every row applies outside it — which was tried
first, and measured, before writing twelve lines instead of one.

Two smaller things the same pass turned up: the panels had no `title`, so VoiceOver announced an
unnamed window for the bar, the palette, the flyouts and the start menu; and a single-window
application read as "running, 1 windows".

**D89. The sound belongs to the application, not to the process making it.**

YouTube in Chrome produced no media row at all, while Control Center showed it — the exact gap D75
predicted we would live with, except this one was ours.

The process CoreAudio names as sending audio out is not the browser. It is
`Google Chrome.app/…/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper`, a
renderer, and a helper is not an `NSRunningApplication`, so
`NSRunningApplication(processIdentifier:)` returns nil and `currentPlayers()` skipped it. Safari and
every Electron application have the same shape.

Two things do know who owns the sound, and both are checked before giving up: the helper's
executable lives inside the owning bundle, so the **outermost** `.app` on its path is the
application (`Google Chrome.app`, not `Google Chrome Helper.app`); and its parent process is usually
the application itself, which covers a helper stored outside the bundle. `launchd` as a parent means
no owner rather than "launchd is playing".

Once the player is named, everything downstream already worked: the row takes its title from the
application's window, and `MediaTitle.clean` strips both `YouTube` and `Google Chrome` off the end.
Verified with the row live: *"Đánh giá Nintendo Switch 2 sau hơn…"*, artist *Google Chrome*.
