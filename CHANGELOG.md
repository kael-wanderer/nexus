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
- Trash row, always present, before Search: click opens it, the context menu opens or empties it
  (through Finder, after a confirmation).
- Drag-to-reorder is back, as an AppKit dragging session (D56): drag a row onto another to move
  it, or drag a running application onto the pinned rows to pin it in that slot.

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
