# More than one monitor

Milestone 20. Which displays carry a bar, and what happens when that changes.

## Three answers, because there are three habits

`appearance.display` (Settings → Appearance → Display):

| Setting | What it does |
|---|---|
| Main display | One bar on the menu-bar display — `NSScreen.screens.first`, never `NSScreen.main`, which follows the key window and wanders |
| Display with the pointer | One bar that moves to whichever monitor the pointer is on, the way the macOS Dock does |
| Every display | A bar on every monitor, all showing the same applications, pinned order, media row and Trash |

A `.specific(uuid)` preference from an older build still resolves — the display is identified by
`CGDisplayCreateUUIDFromDisplayID`, which survives a reconnect where `CGDirectDisplayID` does not
(D11) — and reads as "Main display" in the picker rather than silently rewriting itself.

## Following the pointer

There is no notification for "the pointer crossed to another display". The only event-driven answer
is a global `.mouseMoved` monitor, so one is installed **only** in that mode: it resolves the screen
under the pointer, compares its display identity to the last one, and reframes when it changed. No
timer, nothing polled (D91).

## A bar on every display

One `NonActivatingPanel` per screen, each hosting its own `SidebarView` over the *same*
`SidebarViewModel` — so there is one set of pinned applications, one media row, one Trash state, and
no second set of observers watching the same system.

Consequences worth knowing:

- **The row budget is shared, and sized to the smallest screen.** Zones (M14) are model state; a
  budget that fits a 2560-wide monitor would overflow a 1440-wide one. Every bar fits everywhere.
- **Revealing is shared.** Auto-hide has one revealed state and one trigger strip per screen:
  hovering the edge of the monitor you are on reveals all of them.
- **Hover-expand is shared** for the same reason. It only applies to vertical bars.
- **Panels are created once per display**, not per reframe: the hotkey path must never pay for
  window creation (`design/mvp.md` §2.3).

## What moves with the pointer

The window flyout, the group popover and the palette anchor to the bar **the pointer is on**,
resolved at the moment they open. Clicking an application on the second monitor opens its windows
there.

## Reserved space

`ReservedSpaceController` takes a list of geometries, one per bar, and sweeps each. A window is
measured against the bar on its own display.

Each geometry's screen comes from where its bar *is* — the screen its frame intersects — and not
from the order the preference resolved. The two disagree for a frame or two while a bar is moving
between monitors, and a bar paired with the wrong screen claims that everything on that screen
overlaps it, which pushes windows onto the other monitor (D91).

## Not built

- A per-display edge, width or set of pinned applications. `DisplayOverride` is in the configuration
  and unused.
- Anything that reacts to a display arriving other than a reframe: no per-display saved window
  layouts, no moving other applications' windows back when a monitor returns.
