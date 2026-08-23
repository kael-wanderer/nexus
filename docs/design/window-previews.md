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
