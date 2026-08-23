# Changelog

All notable changes to Nexus. Format based on [Keep a Changelog](https://keepachangelog.com);
this project follows [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- Sidebar on any screen edge: `top` and `bottom` join `left` and `right`. Horizontal bars lay
  rows out along their width; hover-expand is vertical-only (D53).
- Dock Replacement Mode (D51/D52): the macOS Dock hides while Nexus runs and is restored exactly
  when it quits, with the Dock parked on the edge Nexus is not using (D54). Settings → Dock, one
  onboarding step, a menu-bar status row and a Restore button that works whatever the flags say.
- App icon and a menu-bar template icon.
- Trash row, always present, before Search: the macOS Trash icon, full or empty, click opens it,
  the context menu opens or empties it (through Finder, after a confirmation). Full/empty is
  counted with `stat` link counts, so it needs no Full Disk Access (D58).
- An application's windows are now in its context menu, frontmost ticked, one click from the
  sidebar; the thumbnail flyout is renamed Show All Windows (D60).

- Hovering an application opens its window flyout after `behavior.hoverPreviewDelay` (default
  500 ms); moving to another row while one is open switches instantly. Beside a horizontal bar the
  thumbnails sit side by side. Off switch: `behavior.hoverPreview`.

- Start menu (M11, off by default): a browsable grid of every launchable application with a filter
  field, recents first, and Sleep / Restart / Shut Down / Log Out. `general.showStartMenu` adds a
  launcher row at the leading end of the bar; `appearance.startMenuCorner` picks which corner it
  opens from.

- Reserved space (M12, off by default): while the bar is visible and not auto-hiding, windows that
  overlap it are moved off it — pushed if they still fit on what is left of the screen, resized
  only if they do not. Full-screen windows are exempt, and an application that puts its window
  straight back wins (D70). `behavior.reserveSpace`.

- Application groups (M13): drag one icon onto another and hold to put both in a folder, named
  after the category its members declare. A group draws as a 2×2 tile of member icons, opens as a
  popover beside the bar, and can be renamed, reordered, ungrouped or removed. Capacity 9 or 16
  (`behavior.groupCapacity`). Dragging a member out of the popover takes it out of the group.
- Configuration version 2: the dock is a list of entries — applications and groups — rather than a
  list of bundle identifiers. A v1 dock migrates to the same dock in the same order, and the v1
  key is still written so a downgrade keeps working (D72).

- Bar zones (M14): a fixed head (start menu), a scrolling middle (pinned, then running) and a
  fixed tail (Trash, Search). The middle grows until the edge runs out — capacity is measured from
  the screen, and differs between a side edge (height) and a main one (width) — then each section
  scrolls inside itself. `appearance.pinnedLimit` and `appearance.runningLimit` are optional
  ceilings, 0 meaning "fit the screen" (D73, D74). Configuration version 3.

- Now playing (M15, off by default): a row in the bar's tail while something is playing, with
  transport controls that reach any player — including a browser tab — and the track for Music and
  Spotify, which publish it. Hovering opens a flyout with artwork and the three controls.
  `general.showNowPlaying`. No new permission, and no `MediaRemote`: it is private and
  entitlement-gated since macOS 15.4 (D75).

### Fixed
- With enough applications running, Trash and Search scrolled off the end of the bar: everything
  was in one scroll view, clamped to the screen. They now live in a zone that cannot scroll (D73).
- The start menu drew a tile with no caption for any bundle shipping an empty `CFBundleName`; an
  empty name now falls through to the file name like a missing one.
- "Show windows on hover" read as the window list rather than the previews it controls, and the
  General pane drew an empty row where a zero-height view carried an `onAppear`.
- Configuration sections decoded strictly, so adding a field reset the whole section on upgrade;
  every section now decodes field by field (D67).
- The application index listed background agents, helpers and input methods — 454 bundles where
  132 are launchable (D68).
- Window thumbnails were captured and cached but never seen: the flyout panel keeps the frame it
  had when it opened, so an image arriving afterwards was drawn outside it (D65).
- Window-count badges disagreed with the window list: they counted a browser's find bar and
  missed a Finder window. Counts now come from the same Accessibility list the menu shows, and
  the badge is hidden entirely while Accessibility is missing (D61).
- Finder's desktop appeared as a third "Finder" window in its own menu — an element with no AX
  subrole is no longer treated as a window (D62).
- Dragging a running application into the pinned section showed no live preview; only already
  pinned rows moved under the drag (D59).
- Dragging one running application onto another did nothing at all: the running section had no
  user order, only an alphabetical one. It now has both — a stored order for the applications you
  have moved, alphabetical for the rest — and a drag across the separator pins or unpins (D63).
- Drag-to-reorder is back, as an AppKit dragging session (D56): drag a row onto another to move
  it, or drag a running application onto the pinned rows to pin it in that slot. The rows move
  live under the drag and the new order is stored only when the drop lands (D59).

### Fixed
- Clicking a running application whose windows are all closed now shows a window: activation goes
  through LaunchServices, which sends the reopen event the Dock sends, instead of
  `NSRunningApplication.activate()`, which only brings the process forward.
- Closing the onboarding window counts as finishing it, so onboarding no longer reappears on
  every launch.

### Removed
- SwiftUI's `.draggable` on sidebar rows, which never fired — replaced by the AppKit session
  above rather than left as dead code.

## [0.1.0] — 2026-08-22

First MVP. Milestones 1–7 of [`ROADMAP.md`](ROADMAP.md).

### Added

**Foundation**
- SwiftPM package (`NexusCore`, `NexusUI`, `NexusApp`) with a `Makefile` that assembles and signs
  `Nexus.app`. macOS 14+, Swift 6 strict concurrency, no third-party dependencies.
- Agent application (`LSUIElement`) with a menu-bar status item and a single-instance guard.
- Versioned `Codable` configuration in `UserDefaults`: migration framework, corrupt-data
  quarantine, protection against downgrading over a newer file, range clamping.
- `EventBus`, a typed multicast over `AsyncStream`, and `os.Logger` categories with privacy rules.

**Sidebar**
- Non-activating borderless panel that can never become key, so clicking it never disturbs the
  frontmost application's insertion point.
- Left/right position, width, icon size, spacing, corner radius and opacity, all live.
- Pin by dragging an application from Finder, unpin and reorder by drag or context menu.
- Auto-hide with a 2 pt transparent edge-trigger panel; hover expand.
- AppKit context menus that do not activate Nexus.

**Applications**
- Event-driven running-application detection over `NSWorkspace` notifications; no timers.
- Running indicator, active emphasis, window-count badges from `CGWindowListCopyWindowInfo`
  (no permission required).
- Quit and force quit.

**Windows** *(Accessibility)*
- Window enumeration with live titles, minimised state and frames, behind a 250 ms messaging
  timeout on every element.
- One `AXObserver` per application, publishing coalesced change events.
- Window flyout anchored to the sidebar row; click a window to raise it.
- Contextual explain-and-grant screen with live status.
- Optional ScreenCaptureKit thumbnails, captured lazily on hover and cached with a TTL.

**Search**
- Command palette on a global shortcut (`RegisterEventHotKey`, Option+Space by default).
- Providers for applications, windows, files and actions, with per-provider debounce and
  progressive result delivery.
- Deterministic ranking: match quality × provider weight + frecency + state boosts, with
  per-category and global caps.
- Keyboard-first: type, ↑/↓, ⏎, ⇧⏎, ⎋, ⌘1–⌘9. Mouse and hover work too.
- Six built-in actions plus "Quit ⟨app⟩" for every running application.

**Settings and onboarding**
- Settings window: General, Appearance, Behavior, Search, Permissions. Everything applies live.
- Shortcut recorder with real registration validation and rollback.
- Spotlight-conflict guide with a live status read from `com.apple.symbolichotkeys`.
- Launch at login via `SMAppService`.
- Five-step onboarding, every step skippable.

**Polish**
- Reduce Motion and Increase Contrast honoured; VoiceOver labels, values and hints throughout.
- Display identity keyed on display UUID, so the sidebar returns to a reconnected display.
- Accessibility revocation while running degrades cleanly instead of crashing.
- Bounded icon and preview caches.

### Not in this release

Show Desktop and Empty Trash actions, arrow-key navigation of the sidebar, hover-dwell window
flyouts, per-display sidebar configuration UI, and everything in sections 36–110 of the
foundation document (workspaces, widgets, plugins, automation, AI).
