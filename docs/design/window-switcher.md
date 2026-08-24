# Window switcher

Milestone 25. One key opens a full-screen grid of every window on the machine; one click goes
there. Exposé for windows the way the palette is Spotlight for applications — and, like the
palette, it is Nexus's own, so it can carry filtering, grouping and the dock's grouping model
that the system version cannot.

## What exists already

Almost all of the machinery:

- `WindowService`: AX enumeration per application and `allWindows()` across every regular one,
  `activate` (raise, then bring the application forward), a cached snapshot, an unresponsive list.
- `WindowPreviewService`: ScreenCaptureKit captures, downscaled, cached with a 5 s TTL.
- `SearchPanel` / `SearchPanelController`: the pattern for a panel that must take the keyboard and
  give it back, with the non-activating-first strategy and its fallback.
- `HotKeyService`: Carbon slots, one per thing Nexus can be asked to do from anywhere.
- `StringMatching` / `Ranking` / `Frecency`: filtering and recency, already tuned.
- `ApplicationGroup` / `DockEntry`: what a stack in the bar is made of.

So this milestone is a panel, a grid, a bulk capture path, and one new setting tab — not a new
subsystem underneath.

## 1. Shape

A borderless panel the size of the display under the pointer, over everything, dimming the
desktop behind it.

```
┌───────────────────────────────────────────────────────────────┐
│  ▦ ▤ ▥   + Add Stack        ⌕ Filter…          Recent Apps ▾  │  toolbar
├───────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │ ▣ Ghostty ⊗ │  │ ▣ Safari  ⊗ │  │ ▣ Finder  ⊗ │            │
│  │ /Applications│  │ Google      │  │ Macintosh HD│            │
│  │ ┌─────────┐ │  │ ┌─────────┐ │  │ ┌─────────┐ │            │
│  │ │ thumb   │ │  │ │ thumb   │ │  │ │ thumb   │ │            │
│  │ └─────────┘ │  │ └─────────┘ │  │ └─────────┘ │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└───────────────────────────────────────────────────────────────┘
```

One card per window, not per application: two Finder windows are two cards, which is the whole
point — `⌘Tab` already switches applications and cannot reach the second window.

A card carries the application icon, the application name, the window title, and a thumbnail. The
thumbnail is the optional part (§5); everything above it comes from Accessibility and is always
there.

## 2. Opening and closing

**Open:** the global shortcut in `HotKeyService.Slot.windowSwitcher`, default **`⌃⌥W`**.
`⌥Space` is the palette, `⌃⌥Space` is the bar (D101), and `⌘Tab` and `⌃↓` belong to the system.

The panel appears on the display containing the pointer — the same rule the palette uses for its
centred placement, and for the same reason: that is where the user is looking.

**Close:** Escape, clicking a card, clicking the background, or the shortcut again. Losing key
status closes it too, exactly as the palette does. Focus goes back to whatever was frontmost
unless a card was clicked — that card's window is the intended destination.

The panel takes the keyboard, so it inherits the palette's activation strategy verbatim:
non-activating first, `activate-and-restore` from the moment it is observed not to have become
key.

## 3. What is in the grid

Every window `WindowService.allWindows()` returns, minimized ones included and marked. A
minimized window has no capture (§5) and shows its icon; clicking it de-minimises and raises,
which `WindowService.activate` already does.

Enumeration is AX, so it happens **once, on open**, off the main actor, and the panel is put on
screen with whatever the cached snapshot holds while the fresh pass completes. An empty grid for
200 ms is worse than a stale one.

Nexus's own panels are never listed.

## 4. Filter, sort, group

**Filter** is a field in the toolbar, focused on open. It matches application name and window
title through `StringMatching`, so `saf goo` finds Safari's Google window. Empty query is the
whole grid.

**Sort** is a menu: `Recent Apps` (default), `Application`, `Window Title`, with a
reverse toggle beside it. Recency is the order applications were last activated, kept in the view
model from the `EventBus`'s `applicationActivated` and seeded at launch from `Frecency.lastUsed`
— the store the palette already keeps. Within one application, windows hold their AX order, which
is front-to-back.

**Grouping** is three toolbar buttons:

| | |
|---|---|
| Flat | Every window, one grid, sorted as above. |
| By application | A section per application, its icon and name as the header. |
| By display | A section per screen, named by `NSScreen.localizedName`, from the window frame. |

Sort applies inside a section as well as between them. Grouping and sort are remembered in
`NexusConfiguration.behavior`, so the switcher opens the way it was left.

## 5. Thumbnails, and the permission for them

The grid needs many captures at once, and `WindowPreviewService.preview` fetches
`SCShareableContent` per call — twelve windows would be twelve fetches of the most expensive
thing in the path. So the service grows a bulk entry point: one `SCShareableContent` fetch, then
captures in a task group **capped at four in flight**, each result delivered as it lands. The
cache is shared with the hover flyout and its ceiling rises from 32 to 64 entries.

Cards render immediately with the application icon at full card size and swap in the thumbnail
when it arrives. Nothing about the grid waits on ScreenCaptureKit.

Screen Recording is the one place this milestone deliberately departs from
`design/mvp.md` §3.5's "degrade in silence". The first open with previews unavailable shows the
existing `PermissionRequestView` offer inside the panel — one row above the grid, dismissible,
never shown again once dismissed or granted. The grid below it stays fully usable. The reason it
earns a prompt here and not in the flyout: a hover preview is a garnish, whereas a wall of
identical application icons is the switcher failing at its only job.

Accessibility, as everywhere, is not optional — with it denied the panel shows the standard
Accessibility gate and no grid, because there are no windows to list.

## 6. Card actions

- **Click** — `WindowService.activate`, then close the panel.
- **Close button** (hover, top-right of the card) — presses the window's AX close button through
  a new `WindowService.close(WindowIdentity)`. The card leaves the grid on the next
  `windowsChanged`, not optimistically: an unsaved document puts up a sheet and the window is
  still there.
- **Selection** — click with `⌘` toggles a card into a selection set; `Add Stack` acts on it.

## 7. Add Stack

The toolbar's `+ Add Stack` takes the selected cards, reduces them to their distinct bundle
identifiers, and appends `DockEntry.group(ApplicationGroup(...))` to the dock through
`ConfigurationController.update`. It is the same group the bar already draws, auto-named from the
members' category exactly as a group made in the bar is, and it appears in the bar immediately.

Windows are the selection; applications are what is stored. A stack of "these three Safari
windows" would be a promise Nexus cannot keep — window identity does not survive a relaunch, and
a stack that empties itself overnight is worse than no stack. Deliberately not a session
snapshot: restoring frames is `setFrame` on windows that may never come back, and that is a
different milestone.

`Add Stack` is disabled with nothing selected.

## 8. Keyboard

The panel has the keyboard, so it uses it:

| | |
|---|---|
| Type | Filters. The field is focused on open; no need to click it. |
| `←` `→` `↑` `↓` | Moves the selection through the grid, wrapping at the ends of a row. |
| `Return` | Activates the selected card. |
| `⌘W` | Closes the selected window. |
| `Tab` | Moves to the next section when grouped, the next card when flat. |
| `Escape` | Clears a non-empty filter, and closes the panel when the filter is already empty. |

The two-step Escape is what every search field on macOS does, and it is what stops a mistyped
filter from costing the whole panel.

The filter field holds first responder the whole time the panel is open, so the four arrows and
`Tab` are intercepted before the field sees them — through the same local `NSEvent` monitor the
palette uses for its digit chords. Caret movement inside the filter is the price, and it is the
right one: queries here are three or four characters, and a switcher whose arrows do not move the
selection is broken.

## 9. The Shortcuts tab

Nexus has three global shortcuts now — palette, bar focus, switcher — and today two of them live
in unrelated tabs: the palette's in **Search**, the bar's in **Bar**. A third would make the
question "what is bound to what" unanswerable from any one screen.

So the settings window gains a **Shortcuts** tab (`keyboard`), after Behavior, holding all three
rows and nothing else. The two existing recorders move there; their homes lose them rather than
duplicate them. Each row is a `ShortcutRecorder`, a clear button, and a conflict note when two
slots hold the same combination — a state the recorder can already produce and currently reports
nowhere.

This is a move, not a rewrite: `ShortcutRecorder` and the `KeyboardShortcut` bindings are
unchanged.

## 10. Settings

In `general`, beside `focusBarShortcut`, because that is where a global shortcut already lives:

| | |
|---|---|
| `windowSwitcherShortcut` | `KeyboardShortcut?`, default `⌃⌥W`. `nil` switches it off. |


And in `behavior`:

| | |
|---|---|
| `windowSwitcherGrouping` | `flat` / `application` / `display`, default `flat`. |
| `windowSwitcherSort` | `recent` / `application` / `title`, default `recent`, plus a `Bool` for reversed. |
| `windowSwitcherThumbnails` | Default on. Off skips ScreenCaptureKit entirely — icons only, no permission prompt. |

All four decode with `decodeIfPresent` and a default, like every field added since D67.

## Rules it inherits

- Accessibility gates the window list, Screen Recording gates thumbnails (`design/mvp.md` §3, D5).
- Panels never take focus unless they must, and give it back when they do (`design/mvp.md` §2.1).
- No AX traffic on a timer: enumeration happens when the panel opens (§65).
- `.canJoinAllSpaces` and `.fullScreenAuxiliary`, so the switcher opens over a fullscreen
  application without switching Spaces (`design/mvp.md` §2).

## Tests

- Filtering: a query matching an application name, one matching a window title, one matching
  neither, and a query that matches across both fields of different cards.
- Sorting: recency order follows a sequence of `applicationActivated` events; ties inside an
  application keep AX order; reversed is the exact inverse.
- Grouping: sections and their membership for each of the three modes, including a window whose
  frame straddles two displays (it belongs to the one holding its origin).
- Grid navigation: arrows wrap at row ends, `Return` activates the selection, `Escape` clears a
  filter before it closes.
- Bulk previews: one `SCShareableContent` fetch for N windows, never more than four captures in
  flight, cache hits reused, and a denied permission returning nils without throwing.
- Add Stack: a selection of five windows across three applications produces one group of three
  bundle identifiers; an empty selection produces nothing.
- Panel geometry: opens on the display containing the pointer, fills its `visibleFrame`.
- The Shortcuts tab: all three recorders bind their own configuration field, and a duplicate
  combination is reported rather than silently registered twice.
