# Start menu

Milestone 11. A browsable grid of every installed application, opened from a button that sits in
a screen corner.

## Why, given ⌥Space already launches anything

Two different acts. The palette answers *"I know what I want"* — type three letters, hit return.
The start menu answers *"show me what I have"*, which is how anyone finds the utility they use
twice a year and cannot name. Same index, opposite affordance.

## Shape

A panel, not a sheet:

```
┌─────────────────────────────────┐
│  ⌕ Search                       │   filter field, focused on open
├─────────────────────────────────┤
│  ▣ Activity   ▣ Books   ▣ Calc  │   grid of applications, icon + name
│  ▣ Chess      ▣ Clock   ▣ Cod…  │   alphabetical, frecency-ranked first row
│  …                              │
├─────────────────────────────────┤
│  ⏻ Sleep   ⏻ Restart   ⏻ Log Out│   system actions, mirroring the reference
└─────────────────────────────────┘
```

- **Data**: `ApplicationIndex`, already built and cached — 450-odd applications with icons, the
  same source the palette's application provider uses. No new scanning.
- **Ranking**: the existing frecency table puts recently used applications first; the rest is
  alphabetical.
- **Filter field**: reuses `NativeSearchField` and the palette's key handling — arrows move the
  selection, Return launches, Escape closes.
- **System actions**: Sleep / Restart / Log Out / Lock via `NSAppleScript` to System Events,
  behind a confirmation for the destructive ones. Same permission story as Empty Trash (D57).

## The button

An always-present row in the bar, like Trash and Search, at the **leading** end rather than the
trailing one, plus a configurable corner for the panel itself: `startMenuCorner` ∈
{`bottomLeading`, `bottomTrailing`, `topLeading`, `topTrailing`}, defaulting to the corner nearest
the bar's own position.

## Focus

Unlike the sidebar, this panel **must** take focus — it has a text field. It follows the search
palette's design exactly (`design/mvp.md` §2.2): a panel that activates deliberately, restores the
previously frontmost application when dismissed without launching anything, and closes on Escape,
on launch, and when it resigns key.

## Settings

`general.showStartMenu` (default **off** — this is an addition, not a replacement, and the bar
should not grow a button nobody asked for), plus the corner picker and an optional global
shortcut, validated by the same recorder the palette's shortcut uses.

## Tests

- The grid lists what the index holds, frecency first, and filters as characters arrive.
- Escape and launching both restore the previously frontmost application.
- With `showStartMenu = false` the row is absent and `sectionRowCounts` is unchanged.
- Corner placement resolves to the right screen rect for all four corners, including a display
  with a negative origin.
