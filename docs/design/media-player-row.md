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

## Tests

- The row opens no window flyout on hover, ever.
- A player that answers position gets a timeline; one that does not gets the row without it.
- The clock formats a duration as `1:58` and `1:02:07`, and a position past the duration is clamped.
- Dragging the thumb seeks once, on release, with the value under the pointer.
- Position polling starts when the player appears on screen and stops when it goes away.
