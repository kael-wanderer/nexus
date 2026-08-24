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

- **Compact** (a narrow vertical bar): artwork with the waveform badge and a progress line along its
  bottom edge, then the three buttons as a row of their own. Two tiles, because that is what a 64 pt
  bar has.
- **Wide** (a horizontal bar, or a hover-expanded vertical one): the player icon, the track name, the
  timeline with its clocks and the three buttons, all on one row.

**Nothing opens on hover.** Not window previews — the row is not an application — and, since D85,
not a popover either. Everything the player has is on the row.

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
│ ▣  Loki S01 - Newmoon21  ⏮ ⏯ ⏭          │   appearance.mediaContent == .progress
│    ────────●──────────                   │   (the name is free: the row is 72 pt tall)
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

The inline scrubber runs about twelve seconds per point on a 40-minute film. That is the resolution
the bar has, and since D85 it is the only one: coarse for frame-accurate seeking, fine for "back a
bit", and the player's own window is where anyone doing the former is already looking.

## Tests

- The row opens no window flyout on hover, ever.
- A player that answers position gets a timeline; one that does not gets the row without it.
- The clock formats a duration as `1:58` and `1:02:07`, and a position past the duration is clamped.
- Dragging the thumb seeks once, on release, with the value under the pointer.
- Position polling starts when the player appears on screen and stops when it goes away.
- With no player at all, `nowPlayingPlayerName` falls back to a plain "Now Playing" rather than an
  empty header.

## The two bugs it shipped with (D83)

Both from the same assumption — that "somebody is making sound" is the same question as "is there a
player, and is it playing".

- **Pause deleted the player.** Pausing stops the audio, the audio was the only evidence of a player,
  so the row disappeared and took the play button with it. A scriptable player is now asked whether
  it still has something loaded, and keeps its row while it does.
- **The buttons looked broken.** They were landing; the media key was going nowhere. A media key is a
  request to whoever macOS thinks owns playback, and for VLC that is frequently nobody. Transport now
  goes through the player's own scripting dictionary where there is one, with the key as the fallback
  for browser tabs. The play/pause icon follows the player's reported state rather than assuming it
  — and for a browser that state comes from the window title, not from the audio, which keeps
  running while the video is paused (D92, `now-playing.md` §Whether it is playing)
  is playing.

Verified live: clicking play in the bar takes VLC from `playing: false` to `true`; clicking again
pauses it and the row stays, with its title, its position, and a play button.

## The popover, and why it went (D85)

The popover was the player until the wide row existed. Then it was a second copy of the same four
things — artwork, title, timeline, buttons — one hover away from the first, and the row it belonged
to no longer needed it: everything fits on the row itself.

What it uniquely held was a **two-line, untruncated title**. That moved into the row's context menu
as a disabled header, which is where a compact bar — 64 points wide, artwork and a progress line and
nothing else — now shows what is playing.

What it cost, beyond the code: a panel, a hover-out grace period, a re-layout on every track change,
a global click monitor to dismiss it, and an anchor sentinel in `PanelController` for a row that is
not an application. All of that is gone; the group popover and the window flyout keep the machinery
they actually need.

## The compact player's panel came back

Everything above was still true for the *wide* row — but a 64 pt compact row is artwork and a
progress line, nothing else, and the title, the artist and the scrubber D85 moved onto the wide row
had nowhere to go on a narrow bar. So the panel returned for the compact player specifically:
resting on the row opens it after 400 ms, hover-expanding the bar into the wide player closes it
again — the same rule D85 wrote, now enforced for the one case it did not cover rather than assumed
for both. It takes no click monitor, like the window flyout: nothing in it is a commitment.

## The restyle: a chip, a border, and wide tiles

A later pass matched this panel to the same reference screenshot as the window flyout, sharing its
chrome (`design/window-previews.md` §4, `FlyoutPanel.swift`) rather than restyling either alone.

- **The wrapped title block is gone.** The artwork gains a light border and a `LabelChip` — white
  text on a dark rounded tile — over its bottom-leading corner, carrying the track title (D118).
  The trade: the old block wrapped onto up to three lines; a chip truncates to one. The artist line
  underneath is unchanged, and the scrubber stays exactly where it was.
- **The three transport buttons became wide rounded tiles** instead of `MiniTransportButton`'s
  30 pt circles — room enough that the panel reads as a small player in its own right rather than a
  shrunken copy of the row's own buttons.
- **The header is new**: the player's icon and name, `FlyoutHeader`, with no buttons beside them.
  Quit and New Window (`design/window-previews.md` §4) are AX actions on an application; a media
  player is not one, so this panel gets none of them.
- **`behavior.flyoutSize`** sizes the artwork and the tiles here the same way it sizes the window
  flyout's cards (D120) — one setting for both panels, since after this restyle they are one visual
  family and not two popovers that happen to look similar.

Shipped as specified. Nothing here needed a fake beyond what `NowPlayingFlyoutTests` already had —
`nowPlayingPlayerName`'s one deterministic path (no player at all) is covered; the paths through a
real `NSRunningApplication` are not, for the same reason `newWindow()` in the other panel is not.

