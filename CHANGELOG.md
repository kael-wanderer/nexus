# Changelog

All notable changes to Nexus. Format based on [Keep a Changelog](https://keepachangelog.com);
this project follows [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added
- The bar hides on a display showing a native full-screen space, which is what the Dock does. Per
  display: a full-screen window on one monitor leaves the other monitor's bar alone, and the
  edge-reveal strip and reserved space go with it. Detected from the window list on
  `activeSpaceDidChange` — no polling, no permission. `behavior.hideOverFullScreen`, default on,
  Settings → Bar (D111).
- The bar answers a drag properly (M24). An insertion caret is drawn where a reorder would land,
  on the edge the pointer chose, along whichever axis the bar runs. Resting a drag on the middle of
  a group opens its popover after 900 ms, so the drag can carry on inside and be let go on one of
  the tiles — the application lands at that tile's place rather than at the end (D105). A row let go
  outside every Nexus window leaves the bar with the Dock's own puff of smoke; a running row, which
  was never on it, cancels instead (D105).
- Press and hold a pinned row for 600 ms and the bar goes into edit mode: every pinned row grows a
  minus badge on its icon's corner and leans a couple of degrees. Any other click, the pointer
  leaving the bar, or twenty seconds of nothing turns it off. Reduce Motion keeps the badges and
  drops the movement (D107).
- Dock badges (D106): the red label an application puts on its own Dock icon — Mail's unread count,
  a download in progress — mirrored onto the bar's rows, and onto a group when any member has one.
  Read from the Dock's own Accessibility tree, which is the only public route there is; without the
  Accessibility grant there are simply no badges. Never on a timer: it is read when the pointer
  enters the bar and when an application launches or quits.
- Launch feedback: an application that has been asked to launch dims and hops once until it turns
  up, and stops the moment it does. Reduce Motion keeps the dimming and drops the hop.
- A group can carry a colour and an emoji, picked in its popover beside its name or from its context
  menu by name. Stored by colour name rather than as a hex value, and the emoji trimmed to one
  character. `behavior.groupColorsAndEmoji`, default on (D108).
- Hovering a pinned folder shows its stack, after 400 ms, without a click.
  `behavior.folderHoverPreview`, default on (Settings → Bar).
- A newly pinned application joins the group its category already has, and its context menu offers
  that group by name. Nothing is created and nothing is scanned — only a group already on the bar is
  ever used. `behavior.suggestCategoryGroups`, default off (D109).
- `scripts/build-app.sh` and `scripts/make-dmg.sh`: the bundle assembly, the architecture and
  minimum-system guards, the signing chain that keeps TCC grants, and the styled
  drag-to-Applications image, all runnable outside `make`. One architecture per artifact
  (`NEXUS_ARCH`), and the disk image is verified from its own mount — architecture and signature —
  before it is announced. `make app` and `make dmg` call them.

### Fixed
- The minus badge no longer flashes when the pointer moves onto it. It was centred on the icon's
  corner and hung over the tile's edge, so hovering the badge read as leaving the tile — which hid
  the badge, which put the pointer back over the tile. The badge is now kept wholly inside the row
  it decorates, which fixes the bar's edit-mode badges at the same time (D110).
- The same badge flashed a second way even wholly inside the tile: `onHover` is occlusion-sensitive,
  and the badge overlay occluded the very hover that drew it. The hover is now tracked after the
  badge in the modifier chain, so pointing at the badge counts as hovering the tile (D110).
- Grouping applications by dragging, which was "shaky and nearly impossible" (D103). The drag knew
  which row it was on and nothing about where in it, so it reordered the preview on every pointer
  update, which moved the rows under a still pointer, which restarted the 600 ms dwell timer that
  was the only way to ask for a group. Position is now the input: the middle of a row groups, either
  end inserts before or after, the dwell timer is gone, and the same intent is never acted on twice.
  Nothing moves while a group is on offer.
- Two running applications can be grouped. `canGroup` required the target to be in the dock, so two
  loose icons could never become a folder — the one place everybody expects it to work. The target is
  pinned in the same write (D103).
- A drag let go in the gap between two rows, on the section padding, or past the last row no longer
  reverts the whole drag: the bar itself is a drop target, and anywhere inside it commits the
  preview. Outside the bar is still not (D103).
- A folder row could not be dragged at all — `beginDrag` accepted applications and group ids only,
  and a folder wears neither — which is what "reordering a folder silently reverts" was.
- The minus badge in a group's popover did nothing. `nexusRow` overlays an AppKit view to catch
  clicks, and the tile's own catcher was applied after the badge, so it sat on top and the click
  launched the application instead of removing it (D104).
- Renaming a group happens in its title, inline, like an iOS folder: click the name, type, Return.
  The popover takes the keyboard for exactly as long as the field is open and hands it straight back
  to whatever had it — the same bargain the bar's keyboard mode makes. Escape cancels, clicking away
  commits. The alert stays for the row's context menu, which has nowhere to put a field (D104).
- Keyboard control of the bar (M23): `⌃⌥Space` puts the keyboard on the bar. Arrows walk it on either axis, Home and End jump, Return opens the focused
  row, Escape hands the keyboard back to whatever had it. The panel becomes key only while that
  mode is on and stops being key on Escape, on opening a row, on losing key status, or after ten
  seconds of silence (D99). `general.focusBarShortcut`, on by default, Settings → Behavior.
- The Settings scope searches System Settings (D98): every pane — Displays, Keyboard, Screen Time —
  is a result that opens it, read from `/System/Library/ExtensionKit/Extensions` because Spotlight
  does not index the panes on the system volume at all. The scope is renamed **Settings & Actions**,
  which is what it holds.
- Minimized windows in the bar (M22): a fourth part of the fixed tail, before Trash, holding the
  windows you have minimized — newest first, at most three, the owning application's icon with the
  window title when the bar is expanded. Clicking one restores it and brings its application
  forward. Order is kept by Nexus, since `AXMinimized` is a boolean and the window layer has no
  minimise time to give (D97). `behavior.showMinimizedWindows`, default on; off returns the slots
  to the applications.
- Folder stacks (M21): drag a folder from Finder onto the bar and it becomes a row with the
  folder's own icon. Clicking opens what is inside on a grid beside the bar — folders first, then
  files, hidden files skipped, capped at 60 items and read when the stack opens rather than
  watched. A file opens in its default application, a subfolder opens in Finder. A folder macOS
  will not let Nexus read says exactly that, with a button that opens it in Finder; a folder that
  has been deleted says that instead of vanishing from the dock (D96). Configuration version 5.
- A bar on every monitor (M20): `appearance.display` gains **Every display**, so a second screen is
  no longer a dock-free zone — one panel per display over the same model, on every Space of each.
  **Display with the pointer** now really follows it, through a global mouse-moved monitor installed
  only in that mode. Reserved Space takes one geometry per bar, and flyouts open on the bar the
  pointer is on (D91).
- Search scope (M19): one filter over a search — Everything, Applications, Files & Folders, Files,
  Folders, Settings — on `⌃1`…`⌃6`, `⇥` / `⇧⇥` or the chip's menu. Files versus folders is one
  Spotlight clause on the query the file provider already runs, not a second search. The first
  Escape clears the scope, the second closes the palette.
- The bar's Search part can be a box three slots wide instead of an icon (`search.barStyle`).
  The box opens the palette beside itself; the icon, and always the global shortcut, open it in the
  middle of the screen the way Spotlight does (D90). Typing happens in the palette either way — the
  bar cannot take keyboard focus.
- `make install`: the signed bundle goes to `/Applications` and runs from there, with the
  signature preserved so Accessibility and Screen Recording grants survive the move. It refuses to
  install an ad-hoc build (D86). Launch at login is only registered where it can be honoured — the
  Settings toggle says so when Nexus is running from anywhere but an Applications folder.
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
  transport controls that reach any player — including a browser tab. The track comes from Music
  and Spotify where they publish it, and otherwise from the playing application's window title,
  cleaned of file extensions, site names and the application's own name — so VLC reads
  `Loki S01 - Newmoon21` (D76). Hovering opens a flyout with artwork, the track and the three
  controls; the row itself is inset artwork with a waveform badge, so it is not another copy of the
  application's icon. `general.showNowPlaying`. No new permission, and no `MediaRemote`: it is
  private and entitlement-gated since macOS 15.4 (D75).

- The bar is drawn as its six parts, each separated: launcher, pinned, running, now playing, Trash,
  Search (D77).
- Settings → Dock opens with the choice it always was: **Nexus is my Dock** — the macOS Dock stays
  hidden while Nexus runs — or **a sidebar**, which leaves it alone. Two docks at the bottom of the
  screen was nobody's intention (D78).
- Icons default to 64 points, the size of a macOS Dock tile, rather than 40 (D79). Configuration
  version 4 rewrites the old default; a size set by hand is kept.

- The now-playing row is a player rather than an icon (M16): two rows in the bar — artwork with a
  progress line along its bottom edge, and ⏮ ⏯ ⏭ beneath it, no hover needed — and a popover with a
  draggable timeline and a clock. Position comes from Music, Spotify or VLC over their own scripting
  interfaces, once a second while the player is on screen and never otherwise; a player that will
  not say gets the row without a scrubber rather than a fake one (D80).

- The media player can take four slots and show everything inline (M17): a 18 pt icon, the progress
  bar with its clocks — or the track name — and ⏮ ⏯ ⏭, no hover involved.
  `appearance.mediaWidth` (wide, the default, or compact) and `appearance.mediaContent` (progress or
  title). A left or right bar stays compact unless hover has expanded it, because a 56 pt scrubber
  cannot be dragged (D82).

### Changed
- The Definition of Done (§33) walkthrough is recorded in `docs/verification.md`, including the
  30-minute leak soak and the one item that still needs hardware: multi-monitor reconnect.

### Added
- `make dmg` and `make zip`: a signed release build packaged for another Mac, versioned from the
  bundle's own `Info.plist`. Not notarised — the first launch on another machine is right-click →
  Open, which the README now says.
- Settings has an **About** tab (version, build, author, licence, where it is running from, and a
  Copy Version Details button for bug reports) and a **Bar** tab. The panes were re-cut along what
  they are about: Dock is where the bar is, Bar is what it has in it, Appearance is how it looks.
  The window is bigger — sized for the longest pane rather than the average one — and resizable.
- A group's popover is where a group is edited: its title renames it, and hovering a member shows a
  minus badge that takes that application out. Dragging one tile out of sixteen was precise work.

### Fixed
- A horizontal bar is as thick as its icons need. `appearance.width` is the vertical bar's
  measurement, and using it on its side cut the feet off a 64 pt icon in a 64 pt bar — the running
  dots went first (D102).
- The rename alert opens on the screen the click came from. `NSAlert` centres on the main display,
  and re-centres itself as `runModal()` starts, so the move has to happen from inside the modal loop.
- A group with no shared category is named after its members rather than "Group".
- Minimized windows never appeared, because a minimized window stops calling itself a standard
  window: Finder's subrole becomes `AXDialog` in the Dock, and the window list has filtered on
  `AXStandardWindow` since M4. The list now keeps anything minimized as well (D100). The window
  flyout has claimed to show minimized windows since M4 and could not have.
- Dragging a folder or an application from Finder onto the bar does something. The drop was
  SwiftUI's `.dropDestination`, and the AppKit row overlays that own clicks sit on top of it — so a
  drop anywhere over a row, which is most of the bar, was lost. It is an AppKit drop target now.
- The bar's keyboard shortcut fires. `⌃F3` registered and never triggered: macOS owns it for its own
  Dock. Default is `⌃⌥Space`, and a stored `⌃F3` is replaced rather than honoured. Keys are handled
  by the panel rather than by the hosting view, where SwiftUI's own first responder swallowed them
  (D101).
- A group of applications that declare no category is named after its members — "Google Chrome &
  Brave Browser" — instead of "Group".
- Flyouts, group popovers and folder stacks open beside the bar the pointer is on. With a bar on
  every display they anchored to the first one, so clicking a group on the second monitor opened its
  popover on the first.
- The media row goes away when the player quits (D95). It deliberately survives a pause — a paused
  film still has something to resume — but a player that has quit sends no notification saying so,
  and the last track sat there with buttons that reached nobody. The row now clears on
  `.applicationTerminated`, and re-checks that its player is running before drawing at all.
- The menu-bar item says which way it toggles: **Hide Nexus Bar** / **Show Nexus Bar** rather than
  "Toggle Sidebar", which read as a way to move the bar to a side edge and never said whether the
  bar was there (D94).
- Closing the Settings window no longer takes the bars with it (D93): it called `NSApp.hide(nil)`,
  which hides every window an application owns, panels included — leaving the menu-bar item as the
  only sign Nexus was running. Panels now set `canHide = false`, and closing hands focus back by
  activating the application that had it. The same flag was also hiding the bars from VoiceOver.
- The player shows a play triangle when what is playing is paused (D92). A paused browser tab keeps
  its audio unit alive, so CoreAudio still calls it a player; Chrome's window title does not, and
  that is what the state now comes from.
- A window title stops carrying the browser's furniture (D89): a title is cut at the *first*
  segment that is a site name, the application's name, or a browser's note about the tab, so
  Chrome's "… - YouTube - Audio playing - Google Chrome - <profile>" is just the video.
- A browser tab gets a media row again (D89): the process CoreAudio reports as playing is a helper
  — Chrome's renderer, Safari's GPU process — which has no bundle identifier of its own, so the
  player was dropped and YouTube in Chrome produced no row at all. The owning application is now
  resolved from the helper's path and its parent process.
- VoiceOver can now press what it reads (D88): every row adds an accessibility action beside its
  traits, because a panel that cannot become key has no SwiftUI `Button` to inherit one from.
  `AXPress` on the bar, the palette, the flyouts, the start menu and the group popover previously
  reported success and did nothing.
- Panels name themselves, so VoiceOver announces "Nexus", "Nexus Search", "Nexus windows",
  "Nexus group" and "Nexus start menu" instead of an unnamed window.
- An application with one window reads as "running, 1 window".

### Removed
- The media player's popover. The wide row shows artwork, title, timeline and buttons itself, so the
  popover was a second copy of all four, one hover away — and it took a panel, a grace period, a
  click monitor and a re-layout per track with it. The full title now lives in the row's context
  menu, which is where a compact bar needs it (D85).

### Fixed
- The media player's buttons did nothing for VLC, and pausing deleted the player entirely: the row
  existed only while CoreAudio reported sound, and the transport went out as a media key, which
  reaches whoever macOS thinks owns playback — for VLC, usually nobody. Transport now goes through
  the player's own scripting dictionary where there is one, a paused player keeps its row, and the
  play/pause icon follows what the player reports rather than assuming (D83).
- The wide player shows the track name above the progress bar; the row was tall enough for it all
  along (D84).
- Popovers — the window flyout, a group, the media player — now close on a click outside instead of
  only when the pointer leaves. A non-activating panel has no key status to lose, so this needs the
  same global mouse monitor the palette does (D81).
- The search palette stayed on screen when it lost the keyboard: a click in another application, or
  ⌘Tab, now dismisses it, as well as Escape. `hidesOnDeactivate` is off by necessity, so this needs
  a global mouse monitor and a resign-key observer rather than coming for free.
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
