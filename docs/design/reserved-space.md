# Reserved space

Milestone 12. While Nexus is on screen and not hiding, no ordinary window should sit underneath
it — the same deal the macOS Dock gets.

## Why this needs building at all

`NSScreen.visibleFrame` is the menu bar's and the Dock's to shrink. There is no public API that
lets a third-party window reserve screen space, no entitlement for it, and the private
`CGSSetWorkspaceDockRect` route means shipping against an unversioned SPI to fight the very
component we already told to hide. So Nexus cannot make the space unavailable; it can only keep
windows out of it.

Which is what it does, through the Accessibility permission it already holds: watch for windows
that overlap the bar and move them off it.

## Rules

- **Only while the bar is on screen.** `autoHide` on means there is nothing to reserve — a hidden
  bar owns no space. The pass also stops while the bar is suppressed (a full-screen space).
- **Push before shrink.** A window that fits on the remaining screen is moved; only a window too
  wide (or tall) to fit is resized. Moving is reversible in a way resizing is not.
- **Full screen is untouched.** A window with `AXFullScreen` true, or one that covers the whole
  display frame, is left alone — that is the explicit exception in the feature request, and it is
  also the case where the bar hides anyway.
- **Standard windows only.** `kAXStandardWindowSubrole`, as everywhere else (D62). No sheets, no
  panels, no desktop.
- **Never fight an application.** Some windows put themselves back. If one returns to the bar's
  rect twice inside two seconds, it is remembered as unmovable and skipped until its application
  quits. An application that refuses `AXPosition` (not settable) is skipped on the first attempt.
- **No polling.** `AXObserver` per running application: window created, moved, resized, plus
  application activated. One sweep of the frontmost application's windows on enable and on a
  position change, and nothing on a timer (§65).

## Geometry

The interesting part is pure, and gets the tests: given a window frame, the bar's frame and the
bar's edge, return the frame it should have — or `nil` for "leave it". It lives beside the rest of
the layout maths in `SidebarLayout`, which already owns edges and insets.

```
left bar                    bottom bar
┌──┬──────────────┐         ┌────────────────────┐
│▓▓│ ┌──────────┐ │         │ ┌────────────────┐ │
│▓▓│ │  window  │ │         │ │     window     │ │
│▓▓│ └──────────┘ │         │ └────────────────┘ │
└──┴──────────────┘         ├────────────────────┤
   pushed right             │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│  pushed up
                            └────────────────────┘
```

## Settings

`behavior.reserveSpace`, default **off**. It moves other applications' windows and it needs
Accessibility; both make it something to opt into rather than discover. The toggle is disabled with
a caption while `autoHide` is on, and offers the permission prompt when Accessibility is missing —
the same capability pattern as everything else (`mvp.md` §3).

## Not in scope

- Making the space genuinely unavailable, so applications open pre-shrunk. That needs the
  reservation API that does not exist; a window opening over the bar and being nudged a frame later
  is the honest ceiling here.
- Remembering and restoring the frames Nexus changed. Turning the setting off leaves windows where
  they are.

## Tests

- The geometry function: push for each of the four edges, shrink when the window is too large to
  move, `nil` when the window does not overlap, `nil` for a full-display frame.
- With `reserveSpace = false`, or with `autoHide = true`, no observers are registered at all.
- A window that returns twice is skipped the third time (the anti-fight rule), driven through a
  fake AX layer rather than a real application.
