# Nexus — MVP Features

Every feature from Foundation §28, mapped to its milestone and required permission.
Permission column: **None** means the feature works with everything denied.

Legend — M1…M23 = milestone (see `ROADMAP.md`). Rows past 25 are features the MVP did not
have; the Foundation numbering stops there.

---

## MUST HAVE

| # | Feature | Milestone | Permission | Notes |
|---|---|---|---|---|
| 1 | Native macOS application | M1 | None | Agent app (`LSUIElement`), Swift + SwiftUI/AppKit |
| 2 | Vertical sidebar | M2 | None | Non-activating borderless `NSPanel` |
| 3 | Left/right positioning | M2 | None | Live-applied from configuration |
| 4 | App launcher | M2 | None | `NSWorkspace.openApplication` |
| 5 | Running application detection | M3 | None | `NSWorkspace` notifications, event-driven |
| 6 | Launch applications | M2 | None | |
| 7 | Quit applications | M3 | None | `NSRunningApplication.terminate()`; force-quit in context menu |
| 8 | Pin applications | M2 | None | Persisted as ordered bundle identifiers |
| 9 | Reorder applications | M2, M9 | None | Drag any row onto any other — pinned or running — and the rows move live under the drag; the order is stored on drop (D59, D63). Dragging across the separator pins or unpins. Context menu: Move Up / Move Down / Move to End |
| 10 | Window grouping | M4 | **Accessibility** | Flyout listing an app's windows |
| 11 | Activate windows | M4 | **Accessibility** | `AXRaise` + `NSRunningApplication.activate()` |
| 12 | Window count | M3 | None | `CGWindowListCopyWindowInfo` — count only, no titles |
| 13 | Basic window preview | M4, M10 | **Screen Recording** *(optional)* | ScreenCaptureKit; degrades to title-only. Opens on hover after a delay (D64), thumbnails side by side on a horizontal bar |
| 14 | Global keyboard shortcut | M5 | None | `RegisterEventHotKey`; Option+Space default |
| 15 | Search UI | M5 | None | Command-palette `NSPanel` |
| 16 | Application search | M5 | None | In-memory index of `/Applications`, `~/Applications`, system apps |
| 17 | Window search | M5 | **Accessibility** | Provider yields nothing when denied; rest of search unaffected |
| 18 | Basic file search | M5 | None | `NSMetadataQuery` over the user scope |
| 19 | Basic actions | M5 | None | See the Actions table below |
| 20 | Settings | M6 | None | General / Appearance / Behavior / Search / Permissions |
| 21 | Persistence | M1 | None | Versioned `Codable` in `UserDefaults` |
| 22 | Multi-monitor awareness | M2 (basic) → M7 (full) → M20 (bars) | None | Placement at M2; reconnect stability at M7; a bar per display, or one that follows the pointer, at M20 (D91) |
| 23 | Dark/light mode | M2 | None | System materials, no hard-coded colors |
| 24 | Keyboard navigation | M5 (palette) → M7 (sidebar) | None | Palette is keyboard-first from day one |
| 25 | Accessibility basics | every milestone | None | Labels written with the view, not retrofitted; audited at M7 |
| 26 | Install and launch at login | M6 (toggle) → M18 (install) | None | `make install` puts the signed bundle in `/Applications`; `SMAppService.mainApp` registers it there, and the toggle warns when Nexus is running from anywhere else (D86) |
| 27 | Search scope | M19 | None | Everything / Applications / Files & Folders / Files / Folders / Settings & Actions, on `⌃1`…`⌃6`, `⇥` or the chip menu; files versus folders is a Spotlight predicate on the existing query (D87). Settings & Actions holds the built-in actions and every pane of System Settings, read from the extension directory since Spotlight does not index them (D98) |
| 28 | Search box in the bar | M19 | None | `search.barStyle`: an icon in one slot, or a box across three that opens the palette beside itself. The global shortcut always centres the palette (D90) |
| 29 | Folder stacks | M21 | None of Nexus's own; reading Desktop/Documents/Downloads goes through the system's file-access prompt | Drop a folder from Finder onto the bar; clicking opens its contents on a grid beside the bar, folders first, capped at 60. A folder macOS will not let Nexus read says so rather than showing an empty grid (D96) |
| 30 | Minimized windows | M22 | Accessibility (same grant as the window list) | Three rows in the tail before Trash, newest first; click restores. Older ones stay in the application's hover flyout. `behavior.showMinimizedWindows` (D97) |
| 31 | Keyboard control of the bar | M23 | None | `⌃⌥Space` focuses the bar, arrows walk it, Return opens, Escape leaves; the panel is key only while that mode is on, and gives the keyboard back to the application that had it (D99). `⌃F3`, macOS's own Dock shortcut, is owned by the system and never fires (D101) |
| 32 | Packaging | after M23 | None | `make dmg` / `make zip` build a signed release copy for another Mac, versioned from the bundle's own `Info.plist`. Not notarised, so the first launch elsewhere is right-click → Open |

### Basic actions shipped in the MVP (§13)

| Action | Milestone | Permission | Implementation |
|---|---|---|---|
| Quit `<application>` | M5 | None | `NSRunningApplication.terminate()` |
| Open Terminal | M5 | None | `NSWorkspace.openApplication` |
| Open Downloads / Documents / Home | M5 | None | `NSWorkspace.open(URL)` |
| Open System Settings | M5 | None | `x-apple.systempreferences:` URL |
| Show Desktop | — | — | **Not in MVP** — no such bundle exists on macOS 14+; the alternatives need Accessibility or AppleScript (D28) |
| Lock Screen | M5 | None | `SACLockScreenImmediate` (login framework) |
| Start menu | M11 | None (Automation for the system actions) | Browsable grid from the application index, filter field, recents first, Sleep / Restart / Shut Down / Log Out. Off by default; corner configurable |
| Media timeline | M16 | Automation, per player, on first use | Draggable scrubber and clocks for Music, Spotify and VLC, inline in the bar; transport through the player's own scripting interface, media keys as the fallback. Nothing opens on hover (D80, D83, D85) |
| Now playing | M15 | Accessibility (for the title of a player that publishes none) | Row in the tail while something plays: media keys for the controls, distributed notifications or the playing window's title for the track, CoreAudio per-process detection for whether anything plays at all. Off by default (D75, D76) |
| Bar zones | M14 | None | Fixed head and tail, scrolling middle. Capacity measured from the edge — height for a side bar, width for a top or bottom one — with optional ceilings and a two-row floor for running applications (D73, D74) |
| Application groups | M13 | None | Drag one icon onto another and hold; 2×2 tile, popover on click, auto-named from `LSApplicationCategoryType`, capacity 9 or 16. Brings configuration version 2 and the first migration (D71, D72) |
| Reserved space | M12 | Accessibility | Windows overlapping the bar are moved off it — pushed if they fit, resized only if they do not. Full-screen exempt; an application that puts a window back wins after four tries. Off by default. macOS reserves space for no third party, so this moves windows rather than making the space unavailable (D70) |
| Clock and calendar | M27 | None | Time over date at the very end of the bar, two slots, opening the system's own graphical month grid. `TimelineView(.everyMinute)` rather than a timer; locale decides both formats. On by default (D123) |
| Volume | M27 | None | One slot at the end of the bar, the speaker glyph for the current state, opening a slider; right-click mutes. CoreAudio's virtual main volume on the default output device, re-read on every access so headphones do not strand it, with property listeners for the keyboard keys and the menu bar's own slider. On by default (D123) |
| Trash | M9 | None | Always-present row before Search, drawn with the macOS Trash icons and showing full vs empty (counted with `stat`, no Full Disk Access — D58). Click opens it; the context menu opens or empties it, asking first |

No shell execution, no AppleScript, no `osascript` in the MVP. Those need Automation
permission and belong to the automation engine (§46, out of scope).

---

## SHOULD HAVE

| Feature | Milestone | Permission | Notes |
|---|---|---|---|
| Auto-hide | M2 | None | Edge-hover reveal, configurable delay |
| Hover expand | M2 | None | Widened panel with names; must not steal focus |
| Drag and drop | M2 (pin from Finder), M9 (reorder) | None | Dropping an `.app` onto the sidebar pins it. Dragging a row onto another reorders the pins, and dragging a running application onto them pins it in that slot. Dropping files onto an app icon remains out of scope |
| Smooth animations | M2 → M7 | None | Reduce Motion honoured from the first animation written |
| Custom icon size | M2 | None | |
| Custom sidebar width | M2 | None | |
| Custom opacity | M2 | None | |
| Recent applications | M6 | None | Derived from frecency data already collected for ranking |
| Window title preview | M4 | **Accessibility** | Title-only preview; the zero-cost fallback for #13 |
| Spotlight shortcut status | M6 | None | Read-only heuristic on `com.apple.symbolichotkeys` key 64. If readable, the Spotlight guide shows a live "still enabled / disabled ✓" status; if not, the guide is static (review Note 2, D33) |

---

## NICE TO HAVE

| Feature | Milestone | Permission | Decision |
|---|---|---|---|
| Advanced window thumbnails | M7 *(if budget allows)* | **Screen Recording** | Live-ish refresh on hover only; never a capture loop |
| Folder stacks | — | None | **Deferred past MVP.** Not in §33's Definition of Done |
| Multiple sidebar configurations | — | None | **Deferred.** Configuration versioning keeps the door open (§43 profiles) |
| Per-monitor configuration | M7 *(structure only)* | None | Configuration stores a display-keyed dictionary with one entry; UI ships post-MVP |

---

## Added after the MVP (M24)

| Feature | Permission | Notes |
|---|---|---|
| Drag intent zones | None | The middle of a row groups, either end reorders, with an insertion caret on the edge the drop would land on. Anywhere inside the bar commits the drag; outside it unpins a pinned row, with the Dock's poof (D103, D105) |
| Spring-loaded groups | None | Resting a drag on a group opens it, and letting go on a member puts the application at that member's place (D105) |
| Edit mode | None | Press and hold a pinned row for 600 ms: minus badges and a small jiggle, off on any other click. Reduce Motion keeps the badges (D107) |
| Dock badges | **Accessibility** | The red badge label an application sets on its own Dock icon, mirrored onto the bar's rows and onto a group when any member has one. Read from the Dock's Accessibility tree — the only public route — never on a timer, and simply absent without the grant (D106) |
| Launch feedback | None | A launching application dims and hops once until it appears. Reduce Motion keeps the dimming |
| Group colours and emoji | None | Optional per group, edited beside its name or from its menu, stored by colour name. `behavior.groupColorsAndEmoji`, on (D108) |
| Folder preview on hover | None | Resting on a pinned folder opens its stack after 400 ms. `behavior.folderHoverPreview`, on |
| Category suggestions | None | A newly pinned application joins the category group already on the bar, and its menu offers it by name. Nothing created, nothing scanned. `behavior.suggestCategoryGroups`, off (D109) |
| Hide over full-screen apps | None | A display showing a native full-screen space shows no bar, and only that display. Read from the window list on a space change: no polling, no permission. `behavior.hideOverFullScreen`, on (D111) |
| Inline group rename | None | The popover's title is the field, like an iOS folder. The panel is key only while it is open (D104) |

---

## Added after the MVP (M25)

| Feature | Permission | Notes |
|---|---|---|
| Window switcher | **Accessibility**, **Screen Recording** *(optional, thumbnails)* | `⌃⌥W` opens a full-screen grid, one card per window, not per application (D112). Filters by application and window title, sorts by recency / application / title, groups flat / by application / by display — remembered in `behavior`. `general.windowSwitcherShortcut`, default `⌃⌥W`, `nil` off |
| Bulk window previews | **Screen Recording** *(optional)* | One `SCShareableContent` fetch per batch, at most four captures in flight, shared cache raised from 32 to 64 entries (D113). Off entirely with `behavior.windowSwitcherThumbnails` false — icons only, no permission ever asked |
| Add Stack | None | Selecting cards across applications and choosing Add Stack turns their distinct bundle identifiers into a group in the bar, the same kind a stack made in the bar already is (D115) |
| Shortcuts tab | None | Every global shortcut — palette, bar focus, switcher — in one settings tab instead of scattered across the tabs of the features they belong to; flags a conflict when two share a combination (D117) |

---

## Added after the MVP (M26)

| Feature | Permission | Notes |
|---|---|---|
| Restyled hover panels | **Accessibility** *(window titles)*, **Screen Recording** *(optional, thumbnails)* | The window flyout and the now-playing panel share their chrome — the rounded popover material, the header with the application's icon and name, and the title chip over a thumbnail's bottom-leading corner instead of a caption underneath (D118). A hovered card gets an accent ring rather than a tinted background |
| Quit and New Window | **Accessibility** | Two buttons in the window flyout's header. New Window presses the application's own ⌘N menu item through the accessibility tree, off the main thread, and does nothing where no such item exists; Quit asks first, in a confirmation dialog naming the application (D119) |
| Panel size | None | `behavior.flyoutSize` — small, medium or large — sizes both hover panels together, live. Settings → Behavior, beside the hover preview switches (D120) |
| Opened group as a list | None | `behavior.groupLayout`: the grid, or a row per application with its icon beside its name, one width for every group. Clicks, the context menu, dragging a member out and the remove badge are the same either way (D122) |
| Settings search | None | A field above the tabs filters a hand-kept index of every setting by title, by the words it is known under elsewhere, and by its tab; Return or a click goes to the tab holding the match (D121) |

---

## Explicitly out of the MVP (§28, §101)

AI · full automation engine · plugin marketplace · widget system · workspaces and workspace
restoration · cloud sync · accounts · telemetry · remote control · Finder/Terminal/browser
replacement · window tiling and move-to-display (§88) · system control center (§38) ·
diagnostics (§39) · profiles (§43) · Sparkle auto-update (§77) · notarized public
distribution (§111.3).

The architecture must not *block* these (§20). It must not *contain* them.

---

## Permission summary

| Permission | First required | Features lost when denied | Nexus still usable? |
|---|---|---|---|
| **None (M1–M3)** | — | — | Full launcher, pinning, running apps, window counts, settings |
| **Accessibility** | M4 | Window lists, window titles, window activation, window search | Yes — everything above still works |
| **Screen Recording** | M4 *(optional)* | Window thumbnails only | Yes — title-only window lists |

Nexus never requests a permission at launch, never re-prompts after a denial, and never
blocks a feature behind a permission it does not actually need (§25, §64).
