# The media player row

Milestone 16. The now-playing row stops being an application icon with a flyout and becomes what it
is: a player, with its own controls and a timeline you can drag.

## What is wrong with it today

- **It behaves like an application.** Hovering it opens a flyout, the way hovering Safari opens its
  windows. It is not an application row; it is a control, like Trash and Search, and those open
  nothing on hover.
- **The controls are one hover away.** Play, next and previous live in the flyout. For a row whose
  entire job is those three buttons, that is a hover too many.
- **There is no position.** A four-minute song two minutes in looks exactly like one that just
  started, and there is no way to move within it.

## Shape

The row grows into a small player, laid out along the bar:

```
vertical bar (left/right)          horizontal bar (top/bottom)
┌──────────────┐                   ┌────────────────────────────────────┐
│  ▣  Loki S01 │  artwork + title  │ ▣  Loki S01 - Newmoon21            │
│  ⏮  ⏯  ⏭    │  controls         │    ⏮ ⏯ ⏭   ──────●────────  1:58  │
│  ──●───────  │  timeline         └────────────────────────────────────┘
└──────────────┘
```

- **Collapsed** (a narrow bar, no hover): artwork with the waveform badge, exactly as now. The row
  is one tile wide, because that is all a 64 pt bar has.
- **Expanded** (hover-expand on a vertical bar, or a horizontal bar with room): title, three
  buttons, and the timeline inline. No flyout involved.
- **Hover on a collapsed row**: the same player as a popover — because a single tile cannot hold
  three buttons and a scrubber. This is the flyout that exists today, with the timeline added, and
  it opens *immediately* rather than after the preview delay: it is a control, not a preview.

No window previews, ever. The row is not an application.

## The timeline

This is the part that decides how much of the row is real, because position is the one thing macOS
will not tell us for free.

| Player | Position | Seek |
|---|---|---|
| Music, Spotify | `player position` and `duration of current track` over AppleScript | `set player position to n` |
| VLC | `current time` and `duration of current item` | `set current time to n` |
| A browser tab, a game | — | — |

So the timeline appears **only for a player that answers**, and the row is honest when it does not:
controls, title, no scrubber. Automation permission is asked for on first use, per application, the
way Empty Trash does (D57) — and a refusal costs the timeline, nothing else.

Position moves on its own, so it is the one thing in Nexus that may poll: **once a second, only
while the player is on screen** (the expanded row or the open popover), and never otherwise. That
is the same rule the window flyout follows for its thumbnails, and it is worth stating out loud
because §65 forbids polling in general.

## Dragging it

Dragging the scrubber seeks, on release rather than continuously: a seek per pixel would hammer
AppleScript and make a player stutter. While the pointer is down the thumb follows it and the clock
shows the target, so the drag reads as immediate without sending forty of them.

## Settings

None new. `general.showNowPlaying` already decides whether the row exists.

## Rules it inherits

- The popover never takes focus (`design/mvp.md` §2.1), so the scrubber is a drag target, not a
  slider control.
- The metadata rules are unchanged (D75, D76): published where a player publishes, the window title
  otherwise.
- The row lives in the tail (D73), so it survives thirty running applications.

## What shipped

The player, the controls and the timeline, with one thing traded away and one bug worth recording.

**Traded away: inline controls in a wide row.** The sketch above shows the title and the timeline on
one long row beside a horizontal bar. Rows in the bar are one tile each — `sectionExtent` counts
rows, and every piece of layout maths assumes a uniform pitch — so a wide row would mean
variable-extent sections throughout `SidebarLayout`. Not worth it for one row. Instead the player is
**two rows**: the artwork tile, with how far through it is drawn as a line along its bottom edge, and
the three transport buttons beneath. Buttons without a hover, which was the point, and the full
scrubber lives in the popover where there is room to drag it.

**The bug:** `NSAppleScript` ran on the actor's own thread, and it is not thread-safe — the first
build read nothing at all and said nothing about it, because the failure path logged at `.debug`
(memory-only, D66) and the parse path returned `nil` without logging. Scripts now run on the main
actor and every failure is a `.notice`.

Verified live against VLC: the artwork tile carries a progress line at 85%, the buttons sit beside it
in the bar, and the popover shows `Loki S01 - Newmoon21`, `VLC`, a scrubber at `40:21` with `-5:01`
to go, and ⏮ ⏯ ⏭. Position comes from VLC's own scripting dictionary once a second while the player
is on screen, and stops the moment it is not.

## The wide player (M17)

The trade above — two tiles, scrubber in the popover — held for about an hour of use. Four tiles is
the right answer on a horizontal bar, and the layout maths did not have to change to get it: the
wide player is **one view spanning four rows' worth of extent**, so `sectionExtent`, `slots` and
`rowCentre` stay row-based. No variable-pitch sections, which is what made this cheap (D82).

```
┌──────────────────────────────────────────┐
│ ▣  ────────●──────────   ⏮ ⏯ ⏭          │   appearance.mediaContent == .progress
│    27:13        -18:09                   │
└──────────────────────────────────────────┘
┌──────────────────────────────────────────┐
│ ▣  Loki S01 - Newmoon21  ⏮ ⏯ ⏭          │   appearance.mediaContent == .title
│    VLC                                   │
└──────────────────────────────────────────┘
```

- `appearance.mediaWidth` ∈ {`wide`, `compact`}, default **wide**. Compact is the two-tile player.
- `appearance.mediaContent` ∈ {`progress`, `title`}, default **progress**. Title is the fallback
  whatever the setting says, because a scrubber with no position to show is worse than a name.
- The application icon shrinks to 18 pt. It stays because with Spotify paused and VLC playing the
  row has to say which player the buttons will reach.
- **A narrow vertical bar is always compact**, whatever the setting says: four rows of *height* on a
  64 pt bar give a scrubber 56 points long, which is 43 seconds per point on a 40-minute film.
  Hover-expanding a vertical bar makes it wide, since the bar is 220 points then.

The inline scrubber is coarser than the popover's — 200 points across a 40-minute film is about
twelve seconds per point — so the popover stays for precision, and now closes on a click outside
rather than only when the pointer leaves (D81).

## Tests

- The row opens no window flyout on hover, ever.
- A player that answers position gets a timeline; one that does not gets the row without it.
- The clock formats a duration as `1:58` and `1:02:07`, and a position past the duration is clamped.
- Dragging the thumb seeks once, on release, with the value under the pointer.
- Position polling starts when the player appears on screen and stops when it goes away.
