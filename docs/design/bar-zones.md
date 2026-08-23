# Zones: what the bar always shows

Milestone 14. With thirty applications running, Trash and Search scroll off the end of the bar and
have to be hunted for. They are not rows like the others and should never have scrolled.

## The bug, precisely

`SidebarView` puts the whole bar in one `ScrollView`, and `SidebarLayout.frame` clamps the panel to
the screen. Past roughly twenty-four rows the content is longer than the panel, so *everything*
scrolls — the launcher at one end and Trash and Search at the other along with the applications.

## Zones

The bar becomes three parts, and only the middle one scrolls:

```
┌──────────┐   fixed head      start menu (when on)
│ ▦ Apps   │   ───────────
├──────────┤
│ ▣ Safari │   scrolling       pinned applications and groups, up to `pinnedLimit`
│ ▣ Xcode  │   middle          ───────────
│ ▣ Slack  │                   running applications, up to `runningLimit`
│ ▣ Music  │
├──────────┤   ───────────
│ ♫ Track  │   fixed tail      now playing (M15), Trash, Search
│ 🗑 Trash  │
│ ⌕ Search │
└──────────┘
```

The head and the tail keep their rows whatever else happens. The middle gets what is left of the
screen and scrolls inside it.

## Budgets

Two limits, both settings, both counting *rows* — a group is one row, which is the point of groups:

- `appearance.pinnedLimit`, default **10**
- `appearance.runningLimit`, default **5**

The middle's extent is `min(available, pinnedShown + runningShown)`, resolved in that order:

1. The tail and head are subtracted from the screen first. They are never squeezed.
2. Running keeps a floor of **2 rows** whenever anything is running — the ask behind "always show
   1-2 unpinned apps". A dock full of pins must not hide the fact that other applications are open.
3. Pinned takes what remains, up to `pinnedLimit`.
4. Anything over either limit is still reachable: each section scrolls inside its own extent.

So a person with fourteen pins and thirty applications running sees ten pins, two to five running
rows, and can scroll either section. Nothing is hidden, nothing is hunted for.

## Why limits at all, rather than just scrolling

Because scrolling to reach Search was the complaint. A bar that grows without bound turns into a
list; a bar with a budget stays a bar, and the overflow has two better answers already built —
groups for the applications you keep, and the start menu or the palette for the ones you do not.

## Rules it inherits

- `SidebarPosition.isVertical` picks the axis, as everywhere (`design/mvp.md`). Above or below a
  horizontal bar the zones run left-to-right: head at the leading end, tail at the trailing one.
- The panel is still one non-activating panel; zones are layout, not new windows.
- Reserved space (M12) re-sweeps whenever the bar's frame changes, which a zone change is.

## Tests

- With 30 running applications the tail rows are inside the panel's frame, not past it.
- The middle's extent shrinks to fit the screen before either limit is applied.
- Running keeps its two-row floor when the pinned section is over its limit.
- Both limits count a group as one row.
- Horizontal bars put head and tail at the leading and trailing ends.
