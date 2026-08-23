# Nexus — MVP Design

Concrete design for Milestones 1–7. Decisions with reasons; `ARCHITECTURE.md` holds the
module map and cross-cutting rules.

---

## 1. Application shape

Agent application: `LSUIElement = true`, `NSApplication.activationPolicy = .accessory`.
No Dock tile, no menu bar of its own. The only always-visible surfaces are the sidebar panel
and a menu-bar status item (search, show or hide the bar, open Settings, restore the Dock, quit).

`.accessory` (not `.prohibited`) because the search palette must be able to become key, and a
`.prohibited` app cannot activate.

Single instance: on launch, if another process with the same bundle identifier is running,
activate it and exit.

---

## 2. Window hosting — the focus problem

This is the hardest UI problem in the MVP. The sidebar is on screen permanently while the
user works in other applications. **Any focus theft is a product-killing bug**: a lost text
insertion point or a dropped keystroke makes Nexus unusable.

The two panels have opposite requirements and therefore opposite designs.

### 2.1 `SidebarPanel` — must never take focus

```swift
final class SidebarPanel: NSPanel {
    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}
```

| Property | Value | Why |
|---|---|---|
| `styleMask` | `[.borderless, .nonactivatingPanel]` | `.nonactivatingPanel` tells the window server a click here must not activate Nexus |
| `canBecomeKey` / `canBecomeMain` | `false` | The other app's key window keeps its focus and insertion point |
| `level` | `.floating` | Above ordinary windows, below the menu bar and system alerts |
| `collectionBehavior` | `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]` | Present on every Space, over fullscreen apps, and absent from Command-Tab / Exposé |
| `hidesOnDeactivate` | `false` | Nexus is never "active"; the panel must stay |
| `canHide` | `false` | `NSApp.hide(nil)` hides every window an application owns. A bar is not a document window, and an application flagged hidden also publishes no windows to the accessibility tree (D93) |
| `isOpaque` / `backgroundColor` | `false` / `.clear` | Rounded corners and translucency drawn by SwiftUI over `NSVisualEffectView` |
| `isMovableByWindowBackground` | `false` | Position is a setting, not a drag |
| `animationBehavior` | `.none` | Auto-hide animation is ours |

Three consequences of never becoming key, each with a designed answer:

1. **Clicks.** Mouse events reach the window under the cursor whether or not it is key, but a
   click into a non-key window is swallowed unless the view that is *hit* returns
   `acceptsFirstMouse(for:) -> true`. Overriding it on the `NSHostingView` is **not** sufficient:
   the hit view is one of SwiftUI's internal subviews, so SwiftUI's own `.onTapGesture` never
   fires here — and because this panel can never become key, that is true of every click, not
   just the first. Clicks are therefore handled by `PanelRowInteraction`, a small
   `NSViewRepresentable` overlay that claims mouse-press events, returns `acceptsFirstMouse`, and
   tells a click from a drag with a 5 pt slop (D39).

2. **AppKit controls look inactive.** SwiftUI renders standard controls in their inactive
   appearance in a non-key window. The sidebar therefore uses only custom-drawn rows with our
   own hover and pressed states — no `Button` chrome, no focus rings, no `@FocusState`, no
   `.keyboardShortcut` inside this panel.

3. **No keyboard.** Accepted, by design. Keyboard-driven work goes through the search palette
   (§4), which is the keyboard surface. Milestone 7 adds VoiceOver navigation of the sidebar
   through the accessibility element tree, which does not require key status.

Context menus use `NSMenu.popUp(positioning:at:in:)`, which tracks its own event loop from a
non-key window and does not activate the app.

**Drag-to-reorder.** SwiftUI drag-and-drop inside a borderless non-activating panel is the one
piece of this design that is not guaranteed by the documented behaviour of any single API.
Milestone 2 implements it with SwiftUI `.draggable`/`.dropDestination` and verifies it against
the acceptance criterion "clicking or dragging the sidebar never changes the frontmost app".
If it misbehaves, the fallback is a manual reorder in the hosting `NSView` driven by
`mouseDown`/`mouseDragged` — ~60 lines, no focus implications. Decided at implementation time
and recorded in the decision log (`../decisions.md`).

*It misbehaved, and the fallback is what shipped* (D39): `PanelRowInteraction` claims every
mouse-down, runs the drag as an `NSDraggingSession`, and reports where in the row the pointer is —
which is what tells grouping from reordering (D103). The bar's own hosting view is a drop target too,
so a drag let go anywhere inside the bar commits rather than reverting, and one let go outside it
unpins (D105).

**Auto-hide reveal without polling.** While hidden, a 2 pt wide, fully transparent
`EdgeTriggerPanel` sits on the configured screen edge with an `NSTrackingArea`. `mouseEntered`
reveals the sidebar; `mouseExited` on the sidebar plus a 400 ms grace hides it. No global event
monitor, no timer, no permission. Rejected alternative:
`NSEvent.addGlobalMonitorForEvents(.mouseMoved)` — wakes the process on every mouse move for a
feature that fires a few times a minute.

**Do we hide the real Dock?** No. The MVP never touches the user's Dock settings; the design
docs tell the user how to set the Dock to auto-hide if they want. Silently changing a system
setting is exactly the intrusiveness §4 rules out.

### 2.2 `SearchPanel` — must take focus, then give it back

```swift
final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { false }
}
```

`styleMask` `[.borderless, .nonactivatingPanel]`, `level` `.floating`,
`collectionBehavior` `[.canJoinAllSpaces, .fullScreenAuxiliary]`, `hidesOnDeactivate = true`.

`.fullScreenAuxiliary` is what lets the palette appear over a fullscreen app **without
switching Spaces** — the single most noticeable failure mode of a badly built palette.

Two show sequences. The **non-activating** path is tried first; the **activate-and-restore**
path is the fallback. (Amended by review Note 1 — the earlier claim that "a non-active
application's window cannot receive key events, whatever its style mask" is wrong. An
`NSPanel` with `.nonactivatingPanel` and `canBecomeKey = true` *can* become key while the
application stays inactive: the Alfred / LaunchBar pattern.)

**Path A — non-activating (preferred).** The frontmost application never deactivates, so there
is no restore step and no focus flicker.

```
1. previousApplication = NSWorkspace.shared.frontmostApplication   // capture first, either way
2. position the panel on the screen containing NSEvent.mouseLocation
3. panel.makeKeyAndOrderFront(nil)                                  // no NSApp.activate()
4. panel.makeFirstResponder(the search field)
```

Known rough edge, accepted: SwiftUI `TextField` focus is unreliable in a window whose
application is not active, so the field is an `NSTextField` behind `NSViewRepresentable`
(`NativeSearchField`).

**Path B — activate and restore (fallback).**

```
1. previousApplication = NSWorkspace.shared.frontmostApplication
2. position the panel
3. NSApp.activate()                                                 // macOS 14 API
4. panel.makeKeyAndOrderFront(nil)
5. focus the text field, select all existing text
```

**Measured (2026-08-22, unlocked session): Path A works.** `strategy nonActivating, key true,
app active true, frontmost com.apple.TextEdit` — the panel becomes key and accepts typing while
the frontmost application never changes. Path A ships; Path B remains the automatic fallback.

**How the choice is made.** Key status does not settle synchronously, so `SearchPanelController`
starts on Path A and, 200 ms after the first open, logs
`strategy / isKeyWindow / NSApp.isActive / frontmost` and switches permanently to Path B for the
session if the panel did not become key. The decision is therefore made per session on real
evidence rather than baked in. Either way the sidebar's guarantee is untouched: the sidebar
panel still cannot become key.

Dismiss sequence:

```
Escape, resignKey, or an executed action that does not itself activate something
  → panel.orderOut(nil)
  → previousApplication?.activate()        // explicit; deterministic
  → clear the query, drop cached results
```

Explicit reactivation rather than `NSApp.hide(nil)` because `hide` restores whichever app macOS
picks, which is not always the one the user came from.

An action that activates something else (launch app, raise window, open file) skips the
restore — the target application is the intended destination.

### 2.3 Panel ownership

One `@MainActor PanelController` owns every panel, is the only code that touches `NSWindow`,
and rebuilds panel frames on `NSApplication.didChangeScreenParametersNotification`. Panels are
created once and reused; `orderOut`/`orderFront` rather than create/destroy, so there is no
window-creation cost on the hotkey path.

---

## 3. Window management

### 3.1 Enumeration

Two sources, deliberately:

| Need | API | Permission |
|---|---|---|
| Window **count** per app (Milestone 3) | `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)`, filtered to layer 0 and grouped by owner PID | **None** |
| Window **titles**, activation (Milestone 4) | Accessibility API | Accessibility |

Splitting them is what keeps Milestone 3 permission-free (§111.2). `CGWindowList` returns
owner PID, window number and bounds without any grant; only `kCGWindowName` and window images
require Screen Recording.

AX enumeration:

```
AXUIElementCreateApplication(pid)
  → kAXWindowsAttribute        → [AXUIElement]
      → kAXTitleAttribute      → String
      → kAXMinimizedAttribute  → Bool
      → kAXPositionAttribute / kAXSizeAttribute → CGRect
      → _AXUIElementGetWindow  → CGWindowID   (correlates AX ↔ CGWindowList)
```

Every element gets `AXUIElementSetMessagingTimeout(element, 0.25)` immediately after creation.
All of this runs inside the `WindowService` actor, never on the main thread: AX calls are
synchronous IPC into the target application and block for as long as that application is
unresponsive.

`_AXUIElementGetWindow` is a private-ish but long-stable SPI used to get a `CGWindowID` from an
AX element. If it is unavailable, `WindowIdentity` falls back to
`(pid, title, frame)` matching and previews are disabled for that window. Recorded as a known
fragility, not a blocker.

### 3.2 Activation

```swift
AXUIElementSetAttributeValue(window, kAXMinimizedAttribute, false)   // un-minimize if needed
AXUIElementPerformAction(window, kAXRaiseAction as CFString)
runningApplication.activate()                                        // macOS 14 API
```

Order matters: raise before activating, or the app comes forward showing its previous window.

### 3.3 Live updates — no polling

One `AXObserver` per running application, created when the app appears and destroyed when it
terminates, subscribed to `kAXWindowCreatedNotification`,
`kAXUIElementDestroyedNotification`, `kAXTitleChangedNotification`,
`kAXFocusedWindowChangedNotification`, `kAXWindowMiniaturized/DeminiaturizedNotification`.
Observers are added to the main run loop; callbacks hop straight onto the `WindowService`
actor and publish `NexusEvent`s.

### 3.4 Failure handling (§65)

| Condition | `AXError` | Response |
|---|---|---|
| Window closed between enumeration and use | `kAXErrorInvalidUIElement` | Drop it, emit `.windowClosed`, continue. Normal, logged at `.debug` |
| App unresponsive | `kAXErrorCannotComplete` (after timeout) | Skip the app this pass; retry on its next AX event or on the next flyout open. Never retry in a loop |
| Permission missing or revoked at runtime | `kAXErrorAPIDisabled` / `AXIsProcessTrusted() == false` | Tear down observers, publish `.permissionChanged(.accessibility, .denied)`, degrade the UI to Milestone 3 behaviour with an inline notice |
| App terminates mid-call | `kAXErrorInvalidUIElement` | Same as row 1; the `NSWorkspace` termination event cleans up the observer |

Nothing here throws to the user. The user sees a list that is briefly stale, never an alert.

### 3.5 Previews

`SCScreenshotManager.captureImage(contentFilter:configuration:)` (macOS 14+) with an
`SCContentFilter(desktopIndependentWindow:)` matched by `CGWindowID`.

- Captured **lazily on hover**, never on a schedule, never for windows that are not visible.
- Downscaled to a 320 pt maximum dimension at capture time via `SCStreamConfiguration`.
- `NSCache` keyed by `CGWindowID`, cost-limited, entries invalidated on
  `.windowClosed` / `.windowTitleChanged` and after a 5 s TTL.
- Screen Recording denied ⇒ the flyout shows titles only, with one unobtrusive "Enable
  previews" affordance that is never shown again after it is dismissed. No repeat prompting.
- macOS re-prompts for Screen Recording periodically; treat a sudden denial as a normal state
  change, not an error.

---

## 4. Search

### 4.1 Engine

```swift
actor SearchEngine {
    func search(_ query: SearchQuery) -> AsyncStream<SearchSnapshot>
}
```

Progressive delivery, not one final answer: fast in-memory providers emit a first snapshot
within a few milliseconds, and the file provider merges in later. Each call cancels the
previous query's tasks; snapshots carry a query token and stale ones are dropped at the
view-model boundary.

**Debounce, per provider — not globally:**

| Provider | Debounce | Min chars | Reason |
|---|---|---|---|
| Application | 0 ms | 1 | In-memory index; sub-millisecond |
| Window | 0 ms | 1 | In-memory snapshot maintained by `WindowService` |
| Action | 0 ms | 1 | Small static list |
| File | 120 ms | 2 | `NSMetadataQuery` is expensive and returns asynchronously |

A single global debounce would spend the entire 50 ms budget waiting for a result that is
already in memory. Debouncing only the slow provider is what makes the budget achievable.

**Result stability.** Once the user has pressed ↓, a later snapshot must not move the
selection: the view model re-finds the selected result by `id` and keeps it selected; if it is
gone, selection returns to row 0. File results are appended below the fast categories and never
displace the top three rows mid-typing.

**Latency budget (§68).** < 50 ms from keystroke to rendered rows for application and window
results. Measured with `OSSignposter` around `search → snapshot → render` and asserted
manually at Milestone 5.

### 4.2 Providers

| Provider | Source | Permission | Notes |
|---|---|---|---|
| Application | `NSMetadataQuery`, `kMDItemContentType == "com.apple.application-bundle"`, live | None | Spotlight already indexes every app anywhere on disk and pushes updates. Fallback if Spotlight is disabled: one-time scan of `/Applications`, `/Applications/Utilities`, `/System/Applications`, `~/Applications`, refreshed on app launch events |
| Window | In-memory snapshot from `WindowService` | Accessibility | Yields nothing when denied; the rest of search is unaffected |
| File | `NSMetadataQuery`, `kMDItemDisplayName LIKE[cd] "<query>*"`, scope `NSMetadataQueryUserHomeScope` | None | One reusable query object, `stopQuery()` after the initial gather; no live monitoring |
| Action | Static registry (`FEATURES.md` action table) + per-running-app "Quit ⟨app⟩" | None | The seam §81 grows into |

### 4.3 Result model and actions

`SearchResult` carries a `NexusActionDescriptor` **value**, not a closure. Results stay
`Sendable`, comparable and unit-testable without executing anything, and an `ActionRunner` in
the app layer is the single place that performs side effects.

### 4.4 Ranking

Pure functions in `Ranking.swift`, no I/O, the largest unit-test surface in the project.

```
score = matchScore × providerWeight + frecencyBoost + stateBoost
```

**matchScore** — best match over the display name and, for files, the filename:

| Match kind | Score |
|---|---|
| Exact (case/diacritic-insensitive) | 1.00 |
| Prefix of the whole name | 0.90 |
| Prefix of a word (`code` → "Visual Studio **Code**") | 0.80 |
| Acronym / initials (`vsc` → **V**isual **S**tudio **C**ode) | 0.70 |
| Subsequence, scaled by density and gap count | 0.20 – 0.55 |
| No match | excluded |

**providerWeight** — application 1.00, window 0.95, action 0.90, file 0.70. Files rank lowest
because their result set is the largest and least intentional.

**frecencyBoost** — `0.30 × normalizedLaunchCount × exp(-age / 14 days)`, capped at 0.30, from
a per-result-id counter persisted with the configuration. Also the data source for the
"Recent applications" feature.

**stateBoost** — `+0.05` a running application, `+0.03` a window of the frontmost application.

**Tie-break** — shorter title, then title ascending. Deterministic, so tests can assert exact
orderings.

**Caps** — 8 applications, 8 windows, 6 files, 5 actions, 20 total. Category headers in the
UI; no category is ever entirely hidden by another's volume.

### 4.5 Palette interaction

Type · ↑/↓ move · ⏎ execute · ⇧⏎ secondary action (reveal in Finder / new window) ·
⎋ close · ⌘1–⌘9 jump to row · click and hover work. Row 0 is preselected on every new query.
Empty query shows recent items from frecency, not an empty box.

---

## 5. Hotkey

`RegisterEventHotKey` (Carbon HotKey API — still supported, no Accessibility permission) plus
one `InstallEventHandler` for `kEventClassKeyboard` / `kEventHotKeyPressed`, dispatched on the
main run loop. Owned by a `@MainActor HotKeyService`.

Stored as `struct KeyboardShortcut: Codable { keyCode: UInt32; modifiers: UInt32 }` — Carbon
virtual key codes match `NSEvent.keyCode`, so no mapping table is needed for the key itself;
`NSEvent.ModifierFlags` → `cmdKey/optionKey/controlKey/shiftKey` is a four-line conversion.

**Default:** Option+Space (`kVK_Space`, `optionKey`). Development builds ship this and never
ask (§111.1); Milestone 6 onboarding offers the choice.

**Rebinding:** a recorder view using `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`.
Escape cancels, Delete clears. Rules: at least one non-shift modifier required; modifier-only
combinations rejected; the previous binding is restored if `RegisterEventHotKey` returns
anything but `noErr`, with an inline "that shortcut is already in use" message.

**Command+Space is a special case.** Registration *succeeds* but Spotlight still wins, because
the system shortcut is handled ahead of ours — so the failure is undetectable from the return
code. Choosing Command+Space therefore always shows the guide: numbered steps for
System Settings → Keyboard → Keyboard Shortcuts → Spotlight, plus a button that deep-links to
`x-apple.systempreferences:com.apple.Keyboard-Settings.extension`. Nexus cannot perform this
step for the user and says so plainly.

---

## 6. Settings schema v1

> Version 1, as designed for the MVP, kept here for the shape of it. The stored schema is at
> **version 5** now: `pinnedApplications` became `pinnedEntries` — applications, groups (M13) and
> folders (M21) — `perDisplay` was deleted unused, and each milestone since has added its own keys.
> `Sources/NexusCore/Configuration/NexusConfiguration.swift` is the current one, and the migrations
> that get from here to there are in `ConfigurationStore.swift`.

```swift
struct NexusConfiguration: Codable, Sendable, Equatable {
    static let currentVersion = 1
    var version = currentVersion

    var general    = GeneralConfiguration()
    var appearance = AppearanceConfiguration()
    var behavior   = BehaviorConfiguration()
    var search     = SearchConfiguration()
    var pinnedApplications: [String] = []      // ordered bundle identifiers
    var frecency: [String: FrecencyEntry] = [:]
    var onboarding = OnboardingState()
}

struct GeneralConfiguration: Codable, Sendable, Equatable {
    var launchAtLogin = false
    var showInMenuBar = true
    var globalShortcutEnabled = true
}

struct AppearanceConfiguration: Codable, Sendable, Equatable {
    var position: SidebarPosition = .left          // .left | .right
    var width: Double = 64                          // 44...120
    var iconSize: Double = 64                       // 24...96, a Dock tile's own default (D79)
    var iconSpacing: Double = 8                     // 0...24
    var cornerRadius: Double = 16                   // 0...32
    var opacity: Double = 1.0                       // 0.3...1.0
    var display: DisplayPreference = .main          // .main | .withMouse | .specific(uuid)
    var perDisplay: [String: DisplayOverride] = [:] // empty in the MVP; the §14 seam
}

struct BehaviorConfiguration: Codable, Sendable, Equatable {
    var autoHide = false
    var autoHideDelay: Double = 0.4
    var hoverExpand = true
    var showRunningApplications = true
    var showWindowCount = true
    var showFavorites = true
    var clickBehavior: ClickBehavior = .activateOrLaunch  // | .showWindowList
    var reduceMotionOverride: Bool? = nil
}

struct SearchConfiguration: Codable, Sendable, Equatable {
    var shortcut = KeyboardShortcut.optionSpace
    var searchApplications = true
    var searchWindows = true
    var searchFiles = true
    var searchActions = true
    var maximumResults = 20
}

struct OnboardingState: Codable, Sendable, Equatable {
    var hasCompleted = false
    var completedVersion = 0          // re-run onboarding when a future version adds steps
}
```

### Storage and migration (§74)

JSON-encoded into `UserDefaults` under the key `configuration`. `UserDefaults` because it is
the native mechanism, gives atomic writes for free, is inspectable with the `defaults` CLI
during development, and the payload is kilobytes.

```swift
protocol ConfigurationMigration: Sendable {
    var fromVersion: Int { get }                                   // produces fromVersion + 1
    func migrate(_ json: inout [String: Any]) throws
}
```

Migrations operate on the JSON dictionary, not on Swift types, so obsolete versions of the
struct never have to be kept around.

Load path:

1. No stored data → defaults, `onboarding.hasCompleted = false`.
2. Decode `{ "version": Int }` only.
3. `version > currentVersion` → run defaults **in memory**, leave the stored data untouched,
   log a warning. A newer Nexus wrote it; a downgrade must not destroy it.
4. `version < currentVersion` → apply migrations in ascending order.
5. Decode fully. Any failure → copy the raw bytes to `configuration.corrupt.<ISO8601>`, fall
   back to defaults, log. **A bad configuration never crashes Nexus and never silently
   discards the old data.**

Saves are debounced 250 ms, coalesced, and publish `.configurationChanged`. Every setting
applies live; nothing requires a restart.

---

## 7. Onboarding (§111.6, ships with Milestone 6)

Five steps in a standard titled window (not a panel — this one *should* be a normal focused
window). Every step is skippable; skipping applies safe defaults.

1. **Welcome** — what Nexus is, one screen, one Continue button.
2. **Search shortcut** — Option+Space preselected, Command+Space as the alternative. Choosing
   Command+Space reveals the Spotlight guide and the deep link from §5 inline; the step does not
   block on the user actually doing it.
3. **Permissions** — Accessibility (required for window features) and Screen Recording
   (optional, previews). Each row: one plain sentence about what it unlocks, a button that
   opens the exact System Settings pane, and a live status indicator. Status polls at 1 Hz
   **only while this step is visible** — macOS has no TCC change notification, and this is the
   only sanctioned poll in the app (`ARCHITECTURE.md` §5). Both rows are skippable.
4. **Sidebar basics** — left or right, then pin first applications, offering currently running
   applications as candidates.
5. **Done** — the sidebar appears. `onboarding.hasCompleted = true`.

Skipping everything yields: Option+Space, no permissions, left-hand sidebar, no pinned apps —
a fully working launcher, application search and file search. That is the §111.6 requirement
and the acceptance test.

Re-runnable from Settings → General. The same `PermissionRequestView` component is used both
here and by the Milestone 4 contextual prompt, so Milestone 4 builds it first.

---

## 8. Multi-monitor (§14)

**Identity.** `NSScreen` objects and `CGDirectDisplayID`s are both unstable across
disconnect/reconnect. `DisplayService` keys everything on
`CGDisplayCreateUUIDFromDisplayID` → UUID string, which survives reconnection and sleep.

**Placement.** `appearance.display`:

- `.main` (default) — the display with the menu bar.
- `.withMouse` — the display containing the cursor at the moment of the last display change.
- `.specific(uuid)` — a pinned display.

The sidebar frame is derived from `screen.visibleFrame` (not `frame`), so it never overlaps the
menu bar, and inset by `screen.safeAreaInsets` so it clears a notch.

**Change handling.** On `NSApplication.didChangeScreenParametersNotification`, `PanelController`
recomputes the target screen and reframes the sidebar and its edge-trigger panel.
If a `.specific` display is gone, Nexus falls back to the main display **but keeps the stored
preference**, so reconnecting the display restores the sidebar to it without the user touching
Settings.

**Search palette** always opens on the display containing `NSEvent.mouseLocation`, regardless
of the sidebar's display. That is where the user is looking.

**Per-display configuration** was structural only — `appearance.perDisplay`, no UI, no reader —
and has since been deleted. Milestone 20 answered the real question a second monitor asks with
`DisplayPreference.everyDisplay`: a bar per screen, all on the same model, same edge everywhere
(`design/multi-display.md`). A per-display *edge* is still unbuilt, and now unstubbed too: the seam
to reopen is `DisplayPreference`, not a dictionary nobody read (D102's neighbour in `git log`).

---

## 9. Accessibility (§17, §69)

Written with each view, not retrofitted at Milestone 7.

- Every sidebar item: `accessibilityLabel` = application name,
  `accessibilityValue` = "running, 3 windows", `accessibilityHint` = "activates the application".
  Never "Button 42".
- **And an `.accessibilityAction`.** Nothing in these panels is a SwiftUI `Button` — a panel that
  cannot become key cannot host one — so the button trait is a claim with no action behind it, and
  VoiceOver's press does nothing at all (D88). Every row that can be clicked adds the action
  itself, at the call site, next to its traits.
- Every panel sets a `title`, which is never drawn and is what VoiceOver announces on entering the
  window — and `canHide = false`, because an application flagged hidden publishes no windows at all
  to the accessibility tree (D93).
- The search palette is a proper combo-box/list relationship so VoiceOver announces the
  result count and the selected row as the user arrows.
- `@Environment(\.accessibilityReduceMotion)` gates every animation, checked at the call site.
- `@Environment(\.colorSchemeContrast)` drives border and separator opacity.
- System materials and semantic colors only — dark and light mode come for free, and Increase
  Contrast is respected without a second palette.
- User-facing strings go through `String(localized:)` from the start (§70). English only ships,
  but no string is inlined into a view where a translator cannot reach it.

---

## 10. Performance budgets (§18, §68)

| Metric | Target | How it is held |
|---|---|---|
| Cold start | < 1 s to sidebar visible | No index build at launch; Spotlight queries start lazily on first search |
| Idle CPU | ~0 % | Zero timers. Every update is a system event. The one exception is the 1 Hz permission poll on a visible permission screen |
| App / window search | < 50 ms | In-memory providers, zero debounce, progressive snapshots |
| File search | best effort | Debounced 120 ms; results merge in below the fast categories |
| Memory | bounded | `NSCache` for icons and previews with explicit cost limits; previews downscaled at capture, never stored full-size |

Measure before optimising (§68). Signposts, then Instruments at Milestone 7.

---

## 11. Known risks

| Risk | Mitigation |
|---|---|
| SwiftUI drag-and-drop in a non-activating panel | Verified at Milestone 2 against the focus acceptance criterion; manual `NSView` reorder is the fallback (§2.1) |
| `_AXUIElementGetWindow` is SPI | Falls back to `(pid, title, frame)` matching; only previews are lost (§3.1) |
| macOS re-prompting for Screen Recording | Previews are optional by design; a denial is a normal state change (§3.5) |
| Command+Space conflict is undetectable in code | Always show the guide when it is chosen (§5) |
| TCC grants reset if the signature changes | Stable Apple Development certificate and bundle identifier, never ad-hoc (§111.3) |
| Spotlight disabled on the user's machine | Application provider falls back to a directory scan; file search degrades to nothing, and says so |
