# Window previews on hover

Milestone 10. Finishes what `ROADMAP.md` §Milestone 4 already scoped — *"hover or click an app in
the sidebar to list its windows"* — of which only the click half shipped.

## What exists already

- `WindowPreviewService`: ScreenCaptureKit captures, lazy, downscaled, bounded cache, invalidated
  on `windowsChanged`.
- `WindowFlyoutViewModel` / `WindowFlyoutView`: the window list, thumbnails, the Screen Recording
  offer, the Accessibility gate.
- `PanelController`: shows the flyout beside the bar, anchored on the row, with a 400 ms grace
  period before it hides when the pointer leaves.

So this milestone is a trigger, a layout, and a setting — not new machinery.

## 1. Hover intent

Hovering a row opens the flyout after **`hoverPreviewDelay`, default 500 ms**. The timer is
cancelled if the pointer leaves the row before it fires, so sweeping the length of the bar opens
nothing. Moving between rows while a flyout is already open switches it **immediately** — the
delay is the cost of opening, and paying it again per row is what makes hover docks feel sticky.

Rows already prefetch their window titles on hover (D60); the same event starts the timer.

## 2. Layout follows the bar

The flyout is a column of rows beside a vertical bar. Above or below a horizontal bar, thumbnails
sit **side by side** — the shape in the reference screenshot, and the shape the Dock uses.

```
vertical bar            horizontal bar
┌──────────────┐        ┌──────────────────────────────┐
│ ▣ Desktop    │        │  ┌────────┐   ┌────────┐     │
│ ▣ Downloads  │        │  │ ▣      │   │ ▣      │     │
└──────────────┘        │  └────────┘   └────────┘     │
                        │    Desktop      Downloads    │
                        └──────────────────────────────┘
```

`SidebarPosition.isVertical` picks the axis, as everywhere else. Width is capped so a
twelve-window application scrolls rather than spanning the screen.

## 3. Settings

`behavior.hoverPreview` (default **on**) and `behavior.hoverPreviewDelay` (0.2–1.5 s). Off means
today's behaviour exactly: the flyout opens from the context menu's **Show All Windows** only.

`behavior.flyoutSize` (small / medium / large, default medium, Settings → Behavior) picks the card size
— see §4.

## 4. The restyle: cards, a header, and a size setting

A later pass matched the flyout to a reference screenshot, sharing its chrome with the now-playing
panel (`design/media-player-row.md`) rather than restyling either alone.

- **The card is the thumbnail, full-bleed.** The caption that used to sit underneath it is gone;
  the title is a `LabelChip` — white text on a dark rounded tile — over the card's bottom-leading
  corner instead (D118). A hovered card gets an accent-coloured ring where it used to get a tinted
  background, matching the ring in the reference.
- **The header gained two buttons.** Beside the application's icon and name: **New Window**, and
  **Quit**. New Window has no API to call, so it walks the target's AX menu bar for the item bound
  to ⌘N and presses that (D119) — an application that does not map ⌘N to a new window does whatever
  it does map, and the button does nothing rather than guess at a substitute. The walk is
  synchronous IPC into another process, so it runs on `WindowService`'s actor, the same as
  `activate` and `close`, never inline on the button's `onClick` — a menu bar deep enough (or an
  unresponsive application) would otherwise freeze the whole app for up to the AX messaging
  timeout. Quit is `NSRunningApplication.terminate()`, but only from behind a `confirmationDialog`:
  the panel opens on passive hover and terminating another application is not reversible the way
  opening a window is, so a stray click on the button only asks — the dialog's own destructive
  button is what actually quits (D119).
- **`behavior.flyoutSize`** sizes the cards (small/medium/large, default medium — about 340×210 at
  medium). The same setting sizes the now-playing panel's artwork and transport tiles (D120), so
  resizing "the flyouts" is one control, not two that have to be kept in step by hand.
- The vertical-bar row list (`WindowRow`) was left alone beyond inheriting the shared header and
  panel chrome: the reference was the card, and restyling rows too was outside what was approved.

## What shipped

`9cba6bc`, as specified. One thing the spec did not anticipate: a thumbnail arriving *after* the
flyout is on screen has to trigger a re-measure, or it is drawn outside the panel's frame and
never seen (D65).

The restyle in §4 shipped as specified too, including the two header buttons and the size setting.
A whole-branch review moved the AX menu walk off the view model and onto `WindowService.newWindow(for:)`
— the actor already owns the per-application AX elements, the unresponsive-application set, the
trust check, and the `NexusError.timedOut` handling that a menu walk needs exactly as much as
window enumeration does. The view model now just asks the actor through a `Task`, so
`WindowServing`'s fake is what proves it asks for the right application and hides the flyout either
way; the AX walk itself still needs a live process to prove end to end, same as `activate` and
`close` always have.

## Rules it inherits

- Accessibility gates titles, Screen Recording gates thumbnails; without either the flyout still
  lists what it can and never shows an error (`design/mvp.md` §3, D5).
- The flyout is a non-activating panel; hovering it must never steal focus (`design/mvp.md` §2.1).
- No AX traffic on a timer: captures happen when the flyout opens, not while the pointer merely
  passes (§65).

## Tests

- The hover timer fires once, is cancelled on exit before it elapses, and switching rows while
  open skips the delay.
- Flyout frame sits beside a vertical bar and above/below a horizontal one, clamped on screen
  (extends the existing `SidebarLayout` suite).
- `hoverPreview = false` opens nothing on hover, and still opens from the menu.
- Every `FlyoutSize` case has its own card size, artwork size and transport-tile size, and all
  three grow strictly from small to medium to large.
- Quit and New Window both hide the flyout; a target with no matching running process is a no-op,
  not a crash.
- New Window asks `WindowServing` for the target application; the fake records what it was asked,
  closing the coverage gap the AX walk running inline on the view model used to leave.
- Every AX element the menu walk discovers — the menu bar and each child — carries the same
  messaging timeout `windows(of:)` sets on the windows it returns.
- An untitled window still has a readable `displayTitle` ("Untitled window") for the card's chip.
