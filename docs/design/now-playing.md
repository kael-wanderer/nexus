# Now playing

Milestone 15. A row in the bar's fixed tail showing what is playing, with transport controls — the
shape in the reference screenshot: artwork, title, artist, back / play / forward.

## What macOS actually gives us

This is the part worth deciding before any code, because the obvious API is a trap.

- **`MediaRemote.framework`** is what Control Center uses. It is private, and since macOS 15.4 it
  refuses callers without an Apple-internal entitlement. Anything built on it is a feature that
  breaks on somebody's next software update. **Not used.**
- **Media keys** — `NX_KEYTYPE_PLAY`, `_NEXT`, `_PREVIOUS`, posted as system-defined events — are
  how the keyboard's own play button works. They reach whichever application currently owns media
  playback, whatever it is, including a browser tab. This is the control path, and it needs no
  permission beyond the Accessibility grant Nexus already holds.
- **Distributed notifications** carry the metadata: Music posts
  `com.apple.Music.playerInfo` and Spotify posts `com.spotify.client.PlaybackStateChanged`, each
  with the track name, artist, album and player state in the notification's `userInfo`. Public,
  push, no permission, no polling.
- **AppleScript** to a named player would fill in the state on launch, before the first
  notification arrives. It costs an Automation prompt per application (D57), so it is opt-in: the
  row simply says nothing until the next track change otherwise.

## What that means for the row

Two honest states, and the design says which is which rather than pretending:

| | Shown |
|---|---|
| Music or Spotify playing | Artwork, title, artist, and controls, from what they publish. |
| Anything else playing — VLC, a browser tab, a game | Its **window title** as the track, the application's name beneath it, and the same controls (D76). |
| A window with nothing worth reading | Controls, and the word "Playing". No invented title. |
| Nothing playing | The row is absent. The bar does not keep a dead slot. |

The middle row is the one worth explaining. Control Center gets a real title for every player from
`MediaRemote`, which is closed to us — but a player has already told the world what it is playing:
VLC's window is called `Loki S01 - Newmoon21`, and a browser tab is called after the video. Nexus
already reads window titles through Accessibility for the window flyout, so the title is there for
free. What it needs is cleaning: the file extension, the site's name, the application's own name
(`MediaTitle`).

That is a heuristic, and it is treated as one — a window with nothing but the application's name in
it produces no title rather than a bad one.

## Shape

In the bar, one row in the fixed tail (`bar-zones.md`), before Trash:

- Collapsed: artwork at icon size, with a play/pause overlay on hover.
- Hovered: a flyout beside the bar — artwork, title, artist, and the three controls — under the
  window flyout's rules (non-activating, 400 ms grace period, `SidebarLayout.flyoutFrame`).
- Expanded bar (hover-expand on, vertical): title and artist inline, controls beneath.

Artwork comes from the notification when the player supplies it, and falls back to the player's own
application icon, which is always available.

## Settings

`general.showNowPlaying`, default **off** — same reasoning as the start menu: an addition, not a
replacement, and the bar should not grow a row nobody asked for.

## Rules it inherits

- No polling: the row is driven by notifications, and the flyout reads state when it opens (§65).
- The flyout never takes focus (`design/mvp.md` §2.1).
- A missing Automation grant degrades to controls-only rather than to an error (D5).

## What shipped

The row, the flyout and the two honest states as specified. What changed is how "something else is
playing" is answered.

The spec assumed the device-level question — *is the output device in use* — and it is useless in
practice: a browser or a conferencing application holds the device open for hours without making a
sound, so the answer is permanently yes and the row never goes away. It was tried, it stuck on
screen, and it was replaced.

CoreAudio answers **per process** since macOS 14.4: `kAudioProcessPropertyIsRunningOutput` on each
object in `kAudioHardwarePropertyProcessObjectList`. That is exact, and it also names the process —
so a browser tab gets the browser's icon rather than a blank square, which the spec had given up
on. Each process object gets its own listener, because the process *list* does not change when a
process that already exists starts playing. On a system too old for the API the answer is empty and
the row falls back to the players that publish notifications.

Verified live: with VLC playing, the row appears in the tail with VLC's icon and the label
"Playing", and hovering it opens the flyout with the three controls and no invented title. A probe
confirmed VLC was the process actually outputting audio, so the row was right rather than stuck.

Then the row shipped a second time, because an icon and the word "Playing" is not what anyone means
by "what is playing" — and worse, it read as a duplicate of the application's own row a few slots
away. Two changes:

- the title now comes from the playing application's window when it publishes none (D76), so VLC
  reads `Loki S01 - Newmoon21` with `VLC` beneath it;
- the row is drawn as artwork inset on a tinted tile with a waveform badge, so it cannot be mistaken
  for the application's own icon.

Verified live on a bottom bar: the row sits between the separator and Trash with its badge, and
hovering it shows the artwork, `Loki S01 - Newmoon21`, `VLC`, and the three controls.

Not verified live: Music's and Spotify's published metadata (it needs one of them actually playing)
and the keys reaching a player — sending one would have paused somebody's film. Both are unit-tested.

## Tests

- A notification with a track name renders title and artist; one with a stopped state hides the row.
- With no cooperating player, the row shows controls and no title.
- Media-key posting is exercised through an injected sender, so the test does not move the machine's
  actual playback.
- The row lives in the tail: it is present with 30 applications running.
