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

- **Data**: `ApplicationIndex`, already built and cached — the same source the palette's
  application provider uses. No new scanning. Building this made it obvious the index was listing
  every bundle on the disk, agents and helpers included; it now filters to what a person can
  actually launch, 454 down to 132 (D68).
- **Ranking**: the existing frecency table puts recently used applications first; the rest is
  alphabetical.
- **Filter field**: reuses `NativeSearchField` and the palette's key handling — arrows move the
  selection (sideways one at a time, vertically a row at a time), Return launches, Escape closes.
  Filtering, not cross-provider ranking: best match first, then alphabetical, so the grid stays
  stable enough to aim at while you are still typing.
- **System actions**: Sleep / Restart / Shut Down / Log Out via `NSAppleScript` to System Events,
  behind a confirmation for the destructive ones. Same permission story as Empty Trash (D57).
  *Lock was dropped:* macOS exposes it only through a deprecated `CGSession` binary, and Shut Down
  is the action people actually reach for in that row.

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
should not grow a button nobody asked for) plus `appearance.startMenuCorner`.

*Not built:* a dedicated global shortcut. `HotKeyService` holds one binding, and a second one is
its own small piece of work — the launcher row and the menu-bar item are the ways in for now.

## What shipped

`f1b0522`. Two implementation notes worth keeping:

- The panel's height is **computed from the row count**, not measured: a `LazyVGrid` inside a
  `ScrollView` has no intrinsic height, so `fittingSize` sees the field and the action row alone
  and the panel opens as a sliver (D69).
- The menu opens before the application index has finished its first build, so the index calls
  back (`ApplicationIndex.onIndexed`) rather than the menu polling for it.

## Tests

- The grid lists what the index holds, frecency first, and filters as characters arrive.
- Escape and launching both restore the previously frontmost application.
- With `showStartMenu = false` the row is absent and `sectionRowCounts` is unchanged.
- Corner placement resolves to the right screen rect for all four corners, including a display
  with a negative origin.
