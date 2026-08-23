# Minimized windows

**Milestone 22.** A window you minimise should still be somewhere you can see it.

macOS parks minimized windows at the trailing end of its Dock, one tile each, and clicking one puts
it back. Nexus has nowhere for them: minimising a window drops its application's window count by
one and the window itself is only reachable by hovering that application and reading the flyout.
That is a hunt, not a dock.

## Where they go

A fourth part of the fixed tail, immediately before Trash — the same place the macOS Dock puts
them, and the same reason the tail exists at all (M14): a minimized window that scrolled away would
be exactly as lost as it is today.

```
│ ♫ Track   │   fixed tail      now playing (M15)
│ ▫ Draft   │                   minimized windows (M22), newest first, at most 3
│ ▫ Console │
│ 🗑 Trash   │                   Trash
│ ⌕ Search  │                   Search
```

The tail's rows are already counted one section at a time (D77), so a minimized section costs
`min(count, 3)` slots out of the application budget and gives every one of them back when the last
window is restored. Nothing else in the zone maths changes.

## Why three, and what happens to the fourth

Because the tail is subtracted from the applications before they are laid out: an unbounded tail is
a bar that shrinks every time somebody minimises something. Three is enough to make the feature
what it is — the windows you just put down — without the bar rearranging itself around a window
you minimised an hour ago.

Beyond three, the older ones stay exactly where they are today: in their application's hover
flyout, which lists minimized windows and restores them on click. The section is a shortcut to the
recent ones, not the only way back.

## Finding them at all

A minimized window changes its accessibility subrole — Finder's reads `AXDialog` once it is in the
Dock — and the window list has filtered on `AXStandardWindow` since Milestone 4 (D25). So the
section shipped empty: minimising a window made it *leave* the enumeration rather than appear in it
as minimized. The list now keeps a standard window always, and anything minimized unless it calls
itself `AXUnknown` (D100).

## Newest first

The window layer has no minimise timestamp — `AXMinimized` is a boolean, and enumeration order is
whatever the application's window list happens to be. So the order is tracked here: a window that
appears minimized and was not before goes to the front of the list, and a window that stops being
minimized, closes, or whose application quits leaves it. That is what makes the section behave like
the Dock's, where the thing you just minimised is the thing you reach for.

## The row

The owning application's icon, drawn a little smaller than an application row, with the window's
title when the bar is expanded. No thumbnail: previews need Screen Recording (M10), and a tile that
is blank without a permission is worse than one that is honestly an icon. The flyout still shows
thumbnails for anybody who granted it.

Clicking restores: `WindowService.activate` already clears `AXMinimized`, raises the window and
activates its application, which is the whole action. The context menu is the same two items the
flyout's rows carry — Restore, and Show All Windows for the application.

## Permission

Accessibility, which the window list already needs. Without it the section is simply absent, like
every other window feature (`design/mvp.md` §4): nothing to enumerate means nothing to draw.

## Settings

`behavior.showMinimizedWindows`, default **on** — Settings → Behavior, beside the running-application
toggle. Off gives the slots straight back to the applications, the same way switching off the
now-playing row does.

## Tests

- A window that becomes minimized appears in the section; unminimising it, closing it or quitting
  its application takes it out.
- The newest minimized window is first, and stays first when an older one is restored.
- The section is capped at three rows however many windows are minimized, and the count the tail
  reports is the capped one.
- Switching the setting off returns the slots: `tailRowCount` drops by the section's rows.
- Clicking a row calls the same activation path the flyout's rows use.
- With Accessibility denied there is no section at all.

## Acceptance criteria

- Minimising a window puts a row for it in the bar within a second, newest at the top.
- Clicking that row restores the window and brings its application forward.
- Minimising four windows shows three rows; the fourth is still in its application's flyout.
- Restoring every window removes the section, and the applications get their rows back.
