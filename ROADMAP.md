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
- Definition of Done (§33) walkthrough passes end to end on a clean machine. **Walked 2026-08-23:
  everything passes except multi-monitor, which needs a second display; see
  `docs/verification.md`.**
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

## Milestone 12 — Reserved space  ← post-MVP

**Shipped** 2026-08-23.

**Scope**
- While the bar is visible and not auto-hiding, ordinary windows are kept off it: pushed if they
  fit on what is left of the screen, shrunk only if they do not.
- Full-screen windows are exempt. Applications that put a window back twice are left alone.
- `behavior.reserveSpace`, default off — it moves other applications' windows.

**Permissions:** Accessibility, already requested for the window list; the toggle offers the prompt
when it is missing.

**Acceptance criteria**
- A window dropped over the bar is off it within a frame or two, on all four edges.
- `autoHide` on, or the setting off, registers no observers and moves nothing.
- No feedback loop with an application that repositions itself.

Spec: `docs/design/reserved-space.md`.

## Milestone 13 — Application groups  ← post-MVP

**Shipped** 2026-08-23.

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

## Milestone 14 — Bar zones  ← post-MVP

**Shipped** 2026-08-23.

**Scope**
- The bar becomes a fixed head (start menu), a scrolling middle (pinned, then running) and a fixed
  tail (now playing, Trash, Search). Only the middle scrolls.
- Capacity is measured from the edge — a side bar has the screen's height, a main one its width —
  so the bar grows until it runs out and only then scrolls. `appearance.pinnedLimit` and
  `appearance.runningLimit` are optional ceilings (0 = fit the screen), with a two-row floor for
  running so a full dock never hides what is open.

**Permissions:** none new.

**Acceptance criteria**
- With 30 applications running, Trash and Search are inside the panel and need no scrolling.
- The middle shrinks to fit the screen before either limit applies.
- A group counts as one row against the pinned limit.

Spec: `docs/design/bar-zones.md`.

## Milestone 15 — Now playing  ← post-MVP

**Shipped** 2026-08-23.

**Scope**
- A row in the fixed tail: artwork, title and artist for Music and Spotify (distributed
  notifications), transport controls for anything that owns media playback (media keys).
- `general.showNowPlaying`, default off.

**Permissions:** none new — media keys ride on the existing Accessibility grant; metadata arrives by
public notification. `MediaRemote` is deliberately not used: private, and entitlement-gated since
macOS 15.4.

**Acceptance criteria**
- A browser tab playing audio gets working controls and no invented title.
- Nothing playing means no row, not an empty one.
- The row survives 30 running applications, because it lives in the tail.

Spec: `docs/design/now-playing.md`.

## Milestone 16 — The media player row  ← post-MVP

**Shipped** 2026-08-23.

**Scope**
- The now-playing row stops opening a window flyout and becomes a player: artwork, title, the three
  controls inline where there is room, and a popover with the same when there is not.
- A draggable timeline for players that answer their position — Music, Spotify and VLC over
  AppleScript. Players that do not answer get the row without a scrubber rather than a fake one.
- Position is read once a second **while the player is on screen only** — the single sanctioned
  exception to §65, and it stops the moment the player is not visible.

**Permissions:** Automation, per player, on first use (D57). A refusal costs the timeline and
nothing else.

**Acceptance criteria**
- Hovering the row never opens window previews.
- A browser tab gets title and controls, and no timeline.
- Dragging the thumb seeks once, on release, to the value under the pointer.

Spec: `docs/design/media-player-row.md`.

## Milestone 17 — The wide media player  ← post-MVP

**Shipped** 2026-08-23.

**Scope**
- Four slots of bar, with the progress bar and its clocks or the track name inline, an 18 pt player
  icon, and the transport buttons — all without a hover. `appearance.mediaWidth`,
  `appearance.mediaContent`.
- One view spanning four rows' extent, so the layout maths stays row-based (D82).
- A narrow vertical bar stays compact; hover-expanding it makes it wide.
- Popovers close on a click outside (D81) — and the player's own popover is gone, since the row shows
  everything it did (D85).

**Permissions:** none new.

**Acceptance criteria**
- A horizontal bar shows the scrubber, both clocks and the buttons inline, and dragging seeks.
- A 64 pt vertical bar never draws the wide player.
- Clicking anywhere but the bar closes an open popover.

Spec: `docs/design/media-player-row.md` §The wide player.

## Milestone 18 — Install and launch at login  ← post-MVP

**Shipped** 2026-08-23.

**Scope**
- `make install` copies the signed bundle to `/Applications` with `ditto` and runs it from there;
  the running instance is stopped first, because the single-instance guard would otherwise hand the
  launch back to the copy in `build/`. An ad-hoc build is refused.
- Launch at login registers the bundle where it stands, so the Settings toggle says when Nexus is
  running from somewhere a login item cannot survive.

**Permissions:** none new. The signature is unchanged by the move, so existing grants carry over.

**Acceptance criteria**
- The installed application keeps the Accessibility grant — window observers install on first launch
  from `/Applications` without a new prompt.
- Launching the copy in `build/` while the installed one runs activates the installed one and exits.
- Turning on launch at login from `/Applications` leaves `SMAppService` in `.enabled`, and the same
  toggle from a build directory carries the warning instead.

Spec: none — the Makefile target and `LoginItemService` are the whole of it (D86).

## Milestone 19 — Search scope, and opening at the bar  ← post-MVP

**Shipped** 2026-08-23.

**Scope**
- The bar's Search part can be a box across three slots that opens the palette beside itself
  (`search.barStyle`); the global shortcut always centres it, the way Spotlight does (D90).
- A scope filter — Everything, Applications, Files & folders, Files, Folders, Settings — chosen with
  `⌃1`…`⌃6`, `⇥` / `⇧⇥`, or the chip's own menu, shown as a chip in the field, cleared by the first
  Escape. `⌘1`…`⌘6` were already taken by the numbered results (D87).
- Files versus folders is a Spotlight predicate on the existing query, not a second search.

**Permissions:** none new.

**Acceptance criteria**
- A scope narrows results without changing ranking, and never makes a search slower.
- Escape clears a scope before it closes the palette.
- Opening at the bar works on all four edges, clamped on screen.

**Not in scope:** a text field in the bar itself. The sidebar panel can never become key, so a field
drawn there could not be typed into (`design/mvp.md` §2.1).

Spec: `docs/design/search-scope.md`.

## Milestone 20 — More than one monitor  ← post-MVP

**Shipped** 2026-08-23.

**Scope**
- `appearance.display` gains **Every display**: one bar per monitor, all over the same model, so the
  second screen is not a dock-free zone.
- **Display with the pointer** actually follows it, through a global mouse-moved monitor installed
  only in that mode — an event, not a timer.
- Reserved Space takes one geometry per bar, each paired with the screen its bar is really on.
- Flyouts, the group popover and the palette anchor to the bar under the pointer.

**Permissions:** none new.

**Acceptance criteria**
- Every display puts a bar on both monitors, both showing the same applications and the same media
  row, and every Space on each monitor has one.
- Moving the pointer across monitors moves the bar in that mode, and only in that mode.
- A window is pushed off the bar on its own display, and never onto the other monitor.
- One row budget, sized to the smallest screen, so no bar overflows.

Spec: `docs/design/multi-display.md`.

## Milestone 21 — Folder stacks  ← post-MVP

**Shipped** 2026-08-23, verified on the running app — the drop needed an AppKit target before it
worked at all (D39's lesson again).

**Scope**
- `DockEntry` gains `.folder(path)`: a folder is a slot in the dock like an application or a group.
  Configuration version 4 → 5.
- Drag a folder from Finder onto the bar to pin it; the row draws the folder's own icon.
- Clicking opens a popover of the folder's contents beside the bar — the group popover's grid with
  file tiles — read on open, folders first, capped at 60 items.
- A file opens in its default application; a subfolder opens in Finder. Remove from Bar and Open in
  Finder in the row's context menu.
- A folder Nexus may not read says so, with a button that opens it in Finder, rather than drawing
  an empty grid.

**Permissions:** none new of Nexus's own. Reading Desktop, Documents or Downloads goes through the
same macOS file-access prompt any application gets, and a refusal is shown rather than swallowed.

**Acceptance criteria**
- `~/Downloads` dropped on the bar becomes a row with its own icon that survives a restart.
- Clicking it opens the grid beside the bar on the bar's own display; a click outside closes it.
- A file opens, a subfolder opens in Finder.
- A protected folder shows the permission line, not an empty grid.
- Remove from Bar leaves the rest of the dock in order.

Spec: `docs/design/folder-stacks.md`.

## Milestone 22 — Minimized windows  ← post-MVP

**Shipped** 2026-08-23, verified on the running app — the section was empty until D100, because a
minimized window stops calling itself a standard window.

**Scope**
- A fourth part of the fixed tail, before Trash: the windows that have been minimized, newest
  first, at most three rows.
- Order is tracked in Nexus — `AXMinimized` is a boolean and the window layer keeps no minimise
  time — and a window leaves the list when it is restored, closed, or its application quits.
- The row draws the owning application's icon and, when the bar is expanded, the window title.
  Clicking restores through the path the flyout already uses.
- `behavior.showMinimizedWindows`, default on. Off returns the slots to the applications.

**Permissions:** Accessibility, already required for the window list. Denied means no section.

**Acceptance criteria**
- Minimising a window adds a row within a second, newest first; restoring it removes the row.
- Clicking a row restores the window and activates its application.
- Four minimized windows show three rows; the fourth stays reachable in its application's flyout.
- Switching the setting off gives the rows back to the applications.

Spec: `docs/design/minimized-windows.md`.

## Milestone 23 — Keyboard control of the bar  ← post-MVP

**Shipped** 2026-08-23, verified on the running app — and it took two fixes to work outside the
tests: `⌃F3` is owned by macOS, and keys have to be handled by the panel (D101).

**Scope**
- `⌃⌥Space` puts the keyboard on the bar (`⌃F3`, macOS's own Dock shortcut, is eaten by the
  system — D101). Arrows walk it on both
  axes, Home and End jump, Return opens the focused row, Escape gives the keyboard back.
- The sidebar panel becomes key **only** while that mode is on: `acceptsKeyboardFocus`, cleared by
  Escape, by opening a row, by losing key status, and by ten seconds of silence.
- The focused row draws a tinted ring, a shape hover never draws.
- `HotKeyService` registers a shortcut per slot rather than one in total.
- `general.focusBarShortcut`, on by default, with a recorder in Settings → Behavior.

**Permissions:** none. The hotkey is Carbon's, like the palette's.

**Acceptance criteria**
- `⌃⌥Space` rings the first row and arrows move the ring; Return opens what it is on.
- Escape returns the keyboard to the application that had it, with no click in between.
- A shortcut another application owns fails to register and is logged; the bar still works.
- With the setting off, `⌃⌥Space` does nothing.

Spec: `docs/design/keyboard-navigation.md`.

## After Milestone 23

Not a milestone, but shipped alongside the polish round that followed it:

- **Packaging.** `make dmg` and `make zip` build a signed release copy for another Mac, versioned
  from the bundle's own `Info.plist`. Not notarised: that needs a paid Developer ID.
- **Settings, re-cut.** Eight panes — Dock is where the bar is, the new Bar pane is what it shows,
  Appearance is how it looks — in a window sized for the longest one, and an About pane with the
  version, the author and a Copy Version Details button.
- **Editing a group in its popover**: the title renames, a badge on each member removes it.
- **A horizontal bar sizes its own thickness** to the icons it holds (D102).

## After Milestone 23, round two

The hand-testing round that followed M23 found the drag gesture to be the weakest part of the bar,
and the fixes turned into a small milestone of their own (M24). What shipped:

- **Drag intent by position** (D103): the middle of a row groups, either end reorders, with an
  insertion caret where the drop would land. No dwell timer, no preview reset, and two running
  applications can now be grouped.
- **Anywhere in the bar is a drop** (D103), and outside it unpins with the Dock's poof (D105).
- **Spring-loaded groups** (D105), **edit mode** (D107), **Dock badges** (D106), **launch
  feedback**, **group colours and emoji** (D108), **folder previews on hover**, and **category
  suggestions** (D109).
- **Inline group rename** in the popover's own title (D104).
- **The bar hides over full-screen apps**, per display (D111), after a third hand-test round — along
  with a minus badge that stopped flashing once it was kept inside its own row (D110).
- **`scripts/build-app.sh` and `scripts/make-dmg.sh`**, so assembling and packaging a signed build is
  one command each and `make` is only the front door.

## Milestone 25 — Window switcher

**Shipped** 2026-08-24. Spec: `docs/design/window-switcher.md`. What shipped:

- **A full-screen grid**, one key away: `⌃⌥W` opens every window on the machine as one card per
  window rather than per application — `⌘Tab` already reaches applications and cannot reach a
  second window (D112). Minimized windows appear too, marked, with no capture. It opens on the
  display holding the pointer, over a full-screen application, without switching Spaces.
- **Filter, sort, group**: type to filter by application name or window title; sort by recency,
  application or window title, reversible; group flat, by application, or by display. Remembered in
  `behavior.windowSwitcherGrouping` / `windowSwitcherSort` / `windowSwitcherSortReversed`.
- **Bulk thumbnails** (D113): one `SCShareableContent` fetch per batch instead of one per window,
  at most four captures in flight, the shared preview cache's ceiling raised from 32 to 64.
  Screen Recording is the one place this milestone asks for a permission the flyout does not — a
  wall of identical icons is the switcher failing at its only job (D114).
- **Card actions**: click activates and closes the panel; a card's close button presses the
  window's AX close button through the new `WindowService.close`, leaving the card in place until
  the next `windowsChanged` rather than removing it optimistically — an unsaved document still
  shows its sheet. `⌘`-click selects across cards; **Add Stack** turns the selection's distinct
  applications into a group in the bar, the same kind a stack made there already is (D115).
- **Keyboard**: arrows move and wrap at row ends, `Return` activates, `⌘W` closes, `Tab` moves
  between sections. Escape clears a non-empty filter before it closes the panel (D116).
- **A Shortcuts tab**: every global shortcut — palette, bar focus, switcher — in one place instead
  of scattered across the tabs of the features they belong to (D117), with a conflict note when two
  share a combination.

**Permissions:** Accessibility for the window list, Screen Recording optional for thumbnails.

**Acceptance criteria:** see the manual checks in `docs/verification.md` — the switcher itself has
not yet been driven end to end on a running app; the Shortcuts tab has.

## Milestone 26 — The hover panels, groups and settings

**Shipped** 2026-08-24. What shipped:

- **One chrome for both hover panels** — `flyoutPanel()`, `FlyoutHeader`, `LabelChip`. A window's
  card is its thumbnail full-bleed with the title as a chip over the bottom-leading corner rather
  than a caption under it, and a hovered card gets an accent ring (D118). The now-playing panel is
  the same panel with a player's artwork and transport in it.
- **Quit and New Window** in the flyout's header (D119). New Window walks the application's own menu
  bar through the accessibility tree — off the main thread, since that walk can block — and does
  nothing, with a notice in the log, where the application maps ⌘N to nothing. Quit asks first.
- **`behavior.flyoutSize`** (D120), small / medium / large, sizing both panels together and live,
  in Settings → Behavior beside the hover preview switches.
- **An opened group as a list** (D122): a row per application, icon beside name, one width for every
  group, picked by `behavior.groupLayout`. The grid stays the default.
- **Settings search** (D121): a field above the tabs filtering a hand-kept index by title, by the
  words a setting is known under elsewhere, and by its tab, since nine tabs is more than anybody
  reads.

**Acceptance criteria:** the group layouts and the settings picker were driven on screen; the
now-playing restyle, the Quit dialog, the New Window menu walk and typing in the search field are
the manual checks left at the bottom of `docs/verification.md`.

## What is not built, and why

- **Per-display edge and width.** Deleted rather than left half-built: multi-display shipped with
  one edge everywhere, which is what was asked for (see `git log` for `DisplayOverride`).
- **Revealing the bar over a full-screen app by hovering the edge.** Skipped rather than deferred:
  it needs a second visible state — "temporarily over full screen" — with a hide rule of its own,
  since auto-hide's belongs to the auto-hide preference. A bar that reappears over a full-screen
  window is also most of the bug D111 fixes. The preference that turns the hiding off is the escape
  hatch for anybody who wants the bar there.
- **Typing directly into the bar.** Impossible as designed — the panel can never take focus while
  it is a bar (D3). The box in the bar opens the palette beside itself instead (D90).
- **Notarisation.** Needs a paid Developer ID.
- **Update checks.** Blocked, not deferred: there is nowhere to check. It needs a hosted endpoint
  publishing the current version, and no such URL exists yet. Everything else about it — the
  Settings row, the "you are up to date" state — is an afternoon once there is something to ask.
- **Drill-down inside a folder stack, and pagination inside a group.** Both would add a navigation
  stack to a panel that cannot take focus, to save one click to Finder.
