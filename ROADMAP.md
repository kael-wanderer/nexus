# Nexus — Roadmap

Seven milestones, per Foundation §29 (+ onboarding added to Milestone 6 by §111.6).
Each milestone ends with a shippable, stable app: build clean (zero warnings), tests pass,
commit, review. No milestone starts before the previous one is accepted.

Permission policy (§111.2): **Milestones 1–3 require zero permissions.** Accessibility is
first requested in Milestone 4. Screen Recording is always optional.

---

## Milestone 1 — Foundation

Skeleton app that launches, logs, and persists configuration.

**Scope**
- SwiftPM package: `NexusCore`, `NexusApp` (executable), test targets.
- `Makefile` assembling and signing `Nexus.app` (Apple Development cert, stable bundle ID).
- `LSUIElement` agent app: no Dock icon, no menu bar; menu-bar status item is the only
  visible surface (quit + open Settings).
- `NexusConfiguration` v1 (versioned `Codable`), `ConfigurationStore` on `UserDefaults`.
- `EventBus` + domain event types.
- `os.Logger` categories per §66.
- App lifecycle: single-instance guard, launch, terminate.

**Permissions:** none.

**Acceptance criteria**
- `make run` launches the signed app; menu-bar item appears; no Dock icon.
- No crash on launch, quit, or relaunch.
- Configuration written, read back identically after relaunch.
- Corrupt/absent stored configuration falls back to defaults without crashing (test).
- `swift build` and `swift test` succeed with zero warnings.

---

## Milestone 2 — Sidebar

The vertical Dock replacement.

**Scope**
- Non-activating borderless `NSPanel` host (`SidebarPanel`), never becomes key or main.
- SwiftUI `SidebarView` in `NSHostingView`; icon list, separators, search button.
- Left/right position, width, icon size, spacing, corner radius, opacity — all live-bound
  to configuration.
- Pinned applications: add, remove, reorder (drag within sidebar), launch on click.
- Application icons via `NSWorkspace.icon(forFile:)`, cached.
- Auto-hide with screen-edge hover reveal; always-visible mode.
- Context menu: Open, Unpin, Show in Finder.
- Screen placement on the configured display; reacts to `didChangeScreenParameters`.

**Permissions:** none.

**Acceptance criteria**
- Sidebar visible on the chosen edge, above normal windows, on every Space.
- Clicking the sidebar **never** changes the frontmost application, and never removes focus
  from a text field in another app (manual check: type in TextEdit, click sidebar, keep typing).
- Pin, unpin, reorder survive relaunch.
- Launching a pinned app works from a cold and a warm state.
- Auto-hide reveals on edge hover and hides after leaving; Reduce Motion honoured.
- Display disconnect/reconnect leaves the sidebar on a valid screen.

---

## Milestone 3 — Running applications

**Scope**
- `ApplicationService` actor over `NSWorkspace.shared.runningApplications`.
- Event-driven updates: `NSWorkspace.didLaunchApplicationNotification`,
  `didTerminateApplicationNotification`, `didActivateApplicationNotification`. No polling.
- Running indicator dot; active-app emphasis.
- Running-but-unpinned apps appear in their own sidebar section (configurable).
- Quit via `NSRunningApplication.terminate()`, force-quit in the context menu after a timeout.
- Window **count** sourced from `CGWindowListCopyWindowInfo` (no permission, count only —
  titles come at Milestone 4).

**Permissions:** none. `CGWindowListCopyWindowInfo` returns counts and bounds without
Screen Recording; only titles/images are withheld.

**Acceptance criteria**
- Launching or quitting any app updates the sidebar within one runloop tick, no polling timer.
- Window counts track opening/closing windows of a running app.
- Quit from the context menu terminates the app; a refusing app (unsaved document) does not
  hang or crash Nexus.
- Idle CPU measured near zero over a 60 s idle window.

---

## Milestone 4 — Windows  ← first permission gate

**Scope**
- `WindowService` actor over the Accessibility API: enumerate `kAXWindowsAttribute`, read
  `kAXTitleAttribute`, activate via `AXUIElementPerformAction(kAXRaiseAction)` +
  `NSRunningApplication.activate()`.
- `AXObserver` per application for window created/destroyed/title-changed/focus-changed.
- Messaging timeout on every AX element; unresponsive apps degrade, never block.
- Window flyout: hover or click an app in the sidebar to list its windows grouped by app.
- **Accessibility explain-and-grant screen** — contextual, shown the first time a window
  feature is used, with a deep link to System Settings and live grant polling.
- Optional window previews via ScreenCaptureKit, captured lazily on hover, cached, downscaled.
  Declined Screen Recording ⇒ title-only list, no repeated prompting.

**Permissions:** Accessibility (required for this milestone's features).
Screen Recording (optional, previews only).

**Acceptance criteria**
- With Accessibility denied: no crash, no hang; the flyout shows the explain-and-grant screen;
  every Milestone 1–3 feature still works.
- With Accessibility granted: windows listed per app with live titles; clicking one raises it
  and activates its app.
- A window closed by the user disappears from the list without a manual refresh.
- An app that stops responding does not freeze the sidebar (AX timeout ≤ 250 ms).
- Screen Recording denied ⇒ title-only list, no preview placeholders that imply an error.

---

## Milestone 5 — Search

**Scope**
- `SearchPanel`: non-activating `NSPanel` that *can* become key, centred on the active display.
- Global hotkey via `RegisterEventHotKey`; development default **Option+Space**.
- `SearchEngine` actor + `SearchProvider` protocol.
- Providers: Application, Window, File (`NSMetadataQuery`), Action.
- Ranking: match quality × provider weight × frecency. Deterministic and unit-tested.
- Keyboard: type, ↑/↓, Enter, Escape; first result preselected. Mouse works too.
- Focus restoration: closing the palette returns key focus to the previously frontmost app.

**Permissions:** none beyond those already granted. Window results need Accessibility (from
Milestone 4); without it the Window provider yields nothing and the rest still works.

**Acceptance criteria**
- Hotkey opens the palette over a fullscreen app without switching Spaces.
- `code` → Visual Studio Code first result → Enter launches/activates it.
- `bugler.swift` → the file appears → Enter opens it in the default app.
- A running window title matches and Enter raises that window.
- Escape closes and the previously active app regains focus and keyboard input.
- App and window queries render results in **< 50 ms** (measured, logged as a signpost).
- File results arrive asynchronously and never block or reorder the top of the list mid-typing.

---

## Milestone 6 — Settings + onboarding

**Scope**
- Settings window (SwiftUI, `Settings` scene equivalent for an agent app): General,
  Appearance, Behavior, Search, Permissions.
- Shortcut recorder with rebinding; Command+Space selection re-shows the Spotlight guide.
- Launch at login via `SMAppService.mainApp`.
- **First-launch onboarding wizard** per §111.6: Welcome → Shortcut → Permissions →
  Sidebar basics → Done. Every step skippable, skipping applies safe defaults.
- Configuration migration framework exercised by a real v1→v2 migration test.

**Permissions:** none new. The onboarding *offers* Accessibility and Screen Recording;
declining both leaves a fully usable launcher.

**Acceptance criteria**
- Every setting persists across relaunch and applies live without restarting Nexus.
- Onboarding runs exactly once on a clean profile; relaunchable from Settings.
- Choosing Command+Space shows the Spotlight guide and deep-links to the right pane.
- Skipping the entire wizard yields Option+Space, no permissions, working sidebar and search.
- Launch at login toggles the real `SMAppService` state and reflects external changes.

---

## Milestone 7 — Polish

**Scope**
- Animation pass; Reduce Motion and Increase Contrast honoured everywhere.
- Performance: cold start < 1 s, idle CPU ~0 %, resident memory budget documented and measured.
- Accessibility: VoiceOver labels on every interactive element, focus order, full keyboard
  navigation of the sidebar.
- Multi-monitor: display change handling, per-display sidebar placement, stable display
  identity across reconnect (display UUID, not `CGDirectDisplayID`).
- Error handling and permission-revocation recovery (§65).
- Memory: preview cache bounds, icon cache bounds, no retained `CGImage` growth over time.
- README, LICENSE (MIT), CONTRIBUTING, CHANGELOG.

**Permissions:** none new; revocation of any permission must degrade, not crash.

**Acceptance criteria**
- Definition of Done (§33) walkthrough passes end to end on a clean machine.
- Instruments: no leaks, no unbounded growth over a 30-minute session with heavy app churn.
- VoiceOver can drive the sidebar and the search palette without the mouse.
- Revoking Accessibility while running degrades to Milestone 3 behaviour with a clear notice.

## Milestone 8 — Dock replacement  ← post-MVP

**Shipped** 2026-08-23 (`8eafdfe`).

**Scope**
- `SidebarPosition` gains `.top` and `.bottom`; `SidebarLayout` transposed for horizontal edges.
- Dock Replacement Mode: `com.apple.dock` auto-hide with a 1000 s delay, Dock parked on the
  opposite edge, original configuration snapshotted and restored.
- Restore on quit, on toggle off, and on the next launch after a crash; a Restore button in
  Settings and the status menu that never depends on the toggle.
- Settings "Dock" pane and one new onboarding step, both defaulting to off.

**Permissions:** none new. No system files, no `Dock.app` modification, no SIP changes.

**Acceptance criteria**
- All four positions pass the `SidebarLayout` suite, including the `.top` menu-bar case.
- Enabling, quitting and relaunching leaves the Dock exactly as it was found — keys that were
  never set are deleted, not written back with a default.
- Killing Nexus with `SIGKILL` and relaunching restores the Dock.
- Skipping the onboarding step leaves the Dock untouched.

Spec: `docs/design/dock-replacement.md`.

## Milestone 9 — Dock parity  ← post-MVP

**Shipped** 2026-08-23 (`1ec8433`, `319975c`, `b0f86d7`).

**Scope**
- Trash row uses the macOS Trash icons and shows full vs empty, detected with `stat` link counts
  so no Full Disk Access is involved.
- Drag reordering previews live: the dragged row fades, the others move under it, and the
  configuration is written only when the drop lands.
- An application's windows appear directly in its context menu, frontmost ticked; the thumbnail
  flyout stays as "Show All Windows".

**Permissions:** none new. Window titles in the menu need Accessibility, as they already do; the
section is absent without it.

**Acceptance criteria**
- An empty Trash with a `.DS_Store` in it still draws the empty icon.
- A drag that is cancelled or dropped outside the sidebar leaves the stored order untouched.
- Right-clicking a two-window application offers both windows and raises the one clicked.
- The context menu never waits on Accessibility; a row with no cached windows shows no section.

Spec: `docs/design/dock-parity.md`.

## Milestone 10 — Window previews on hover  ← post-MVP

**Shipped** 2026-08-23 (`9cba6bc`).

**Scope**
- Hovering an application opens its window flyout after a delay; leaving before it elapses opens
  nothing, and moving to another row while one is open switches immediately.
- Thumbnails sit side by side above or below a horizontal bar, in a column beside a vertical one.
- `behavior.hoverPreview` and `behavior.hoverPreviewDelay` in Settings; off restores today's
  menu-only behaviour.

**Permissions:** none new. Accessibility gates titles, Screen Recording gates thumbnails — both
already handled by the flyout.

**Acceptance criteria**
- Sweeping the pointer across the whole bar opens no flyout.
- The flyout never takes focus, at any position.
- Screen Recording denied ⇒ titles only, no placeholder that implies an error.

Spec: `docs/design/window-previews.md`.

## Milestone 11 — Start menu  ← post-MVP

**Shipped** 2026-08-23 (`f1b0522`).

**Scope**
- A browsable grid of every installed application, from the existing `ApplicationIndex`, with a
  filter field, frecency-first ordering and system actions (Sleep / Restart / Log Out / Lock).
- A launcher button at the leading end of the bar and a configurable corner for the panel.
- `general.showStartMenu`, default off, plus an optional global shortcut.

**Permissions:** none new; the system actions use Automation, requested on first use like Empty
Trash (D57).

**Acceptance criteria**
- Escape or launching restores the previously frontmost application.
- With the setting off, the bar has no launcher row and the layout is byte-identical to today.
- All four corners resolve correctly, including on a display with a negative origin.

Spec: `docs/design/start-menu.md`.

## Milestone 12 — Application groups  ← post-MVP

**Scope**
- Drop one application onto another to make a folder; a popover grid opens it; the name is
  auto-generated from `LSApplicationCategoryType` and editable; capacity 9 or 16.
- `pinnedApplications: [String]` becomes a list of entries that are either an application or a
  group, taking the configuration from version 1 to version 2 — the first real migration.

**Permissions:** none new.

**Acceptance criteria**
- A version 1 configuration loads into version 2 with the same dock in the same order.
- A group of one dissolves; a full group refuses a drop visibly rather than silently.
- A group whose applications have all been uninstalled disappears without taking the dock with it.

Spec: `docs/design/app-groups.md`.

