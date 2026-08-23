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
| Music or Spotify playing | Artwork, title, artist, and controls. The real thing. |
| Anything else playing — a browser tab, VLC, a game | Controls only, labelled "Playing". |
| Nothing playing | The row is absent. The bar does not keep a dead slot. |

Controls work in both cases, because media keys do not care who is playing. Only the *title* needs
a cooperating application. Trying to hide that difference would mean scraping window titles, which
is guesswork dressed up as a feature.

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

## Tests

- A notification with a track name renders title and artist; one with a stopped state hides the row.
- With no cooperating player, the row shows controls and no title.
- Media-key posting is exercised through an injected sender, so the test does not move the machine's
  actual playback.
- The row lives in the tail: it is present with 30 applications running.
