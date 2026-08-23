# Decisions — Now playing

What is playing, who is playing it, and whether it is playing at all.

Part of the decision log; the index, and the rule these follow, are in
[`../decisions.md`](../decisions.md). Numbers are global and never reused, so the gaps
here are entries that live in another file, and the date each was made is in `git log`.

## D75. What is playing comes from public sources, or not at all.
`MediaRemote.framework` is what Control Center uses and would answer for every player at once. It
is private, and since macOS 15.4 it refuses callers without an Apple-internal entitlement: building
on it means shipping a feature that breaks on somebody's next software update. So Nexus asks three
public questions instead and shows exactly what they answer:

- **The track** comes from the distributed notifications Music and Spotify already post on every
  change (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`). Push, no
  permission, and both use the same keys, which is why one parser covers them.
- **The controls** are media keys — the system-defined events a keyboard's transport keys send.
  They reach whichever application owns playback, including a browser tab, and need no permission
  beyond the Accessibility grant Nexus already holds.
- **Whether anything is playing at all** is CoreAudio's per-process answer,
  `kAudioProcessPropertyIsRunningOutput`. The device-level version of that question was tried first
  and is useless: a browser holds the output device open for hours in silence, so the row never went
  away. Per process it is exact, and it names the process — which is what gives a browser tab an
  icon instead of a blank square.

What none of them give is a title for a player that publishes none, so the row shows controls and
the word "Playing" rather than scraping a window title and calling it a track. Artwork is the same
story: neither notification carries an image, so the row draws the player's own icon.

## D76. A player that publishes nothing is named by its window.
D75 settled for controls and the word "Playing" for anything that is not Music or Spotify, on the
grounds that scraping a window title is guesswork. Using it made the answer obvious: an icon and
"Playing" is not what anyone means by *what is playing*, and it read as a duplicate of the
application's own row a few slots away.

The window title is not a guess for this purpose — it is what the player has already published to
every window list on the system. VLC names the file, a browser names the tab, and Nexus already
reads window titles through Accessibility for the flyout. So the title of the frontmost window of
the application CoreAudio says is making the sound becomes the track, after `MediaTitle` strips the
furniture: the media extension, the site's name (`… - YouTube`), and the application's own name.

It is still a heuristic and is treated as one. A window with nothing but the application's name in
it yields no title rather than a wrong one, published metadata always wins when it exists, and the
row is drawn as inset artwork with a waveform badge so it can never be confused with the
application's own icon.

## D80. Position is asked for, per player, and only while somebody is looking.
`MediaRemote` would have reported position for every player at once, and it is closed (D75).
Nothing public reports how far into a video a browser tab is — so the timeline exists for the
players that ship a scripting dictionary (Music, Spotify, VLC) and is simply absent for the rest.
Absent, not faked: a row without a scrubber is honest, a scrubber that does not move is a bug that
looks like a feature.

That makes position the one thing in Nexus that is polled, since no notification carries it. The
poll is bounded by visibility rather than by frequency: once a second, and only while the player is
actually on screen — the expanded row or the open popover. It stops when the popover closes.
Seeking is a single write on release rather than one per pixel, because each one is an AppleScript
round trip and a player that receives forty of them stutters.

Two implementation notes. Spotify reports its duration in milliseconds where Music and VLC report
seconds, which is the kind of difference that silently turns a four-minute song into a
four-thousand-second one. And `NSAppleScript` is not thread-safe: run from an actor's own thread it
read nothing at all, and said nothing, because the failure path logged at `.debug` — the D66 lesson,
learned twice.

## D83. The player asks the player, and a paused player keeps its row.
Two bugs with one cause: the row's existence and its play state were both inferred from CoreAudio
saying somebody was making sound.

- **Pausing deleted the player.** Pause stops the audio, the audio was the only evidence, so the row
  vanished — leaving nothing to press play on. A player that can be asked is now *asked*: while it
  still has something loaded, the row stays and shows a play button. A player that stops answering
  loses its row, and a browser tab — which cannot be asked anything — loses it when the sound stops,
  which is the best available answer.
- **The button always showed pause.** `isPlaying` was hard-coded true on the fallback path, so it
  never became a play button. Scriptable players report their own state; for the rest, making sound
  is still the only evidence there is.

Transport now goes through a script where the player has a dictionary, and falls back to a media key
where it does not. A media key is a request to whoever macOS thinks owns playback, which is not
always the player on the row and in VLC's case is often nobody at all — which is why the buttons
looked broken even when the click was landing. The keys stay for browser tabs, which no dictionary
covers.

## D84. The wide player's title goes above the scrubber, not instead of it.
The row is 72 points tall and the scrubber with its clocks needs about 40, so the name is free.
`mediaContent` still chooses what the middle is *for* — a scrubber with a name over it, or the track
and artist alone — but the progress mode no longer hides what is playing.

## D85. The media player has no popover.
It had one because for a while it *was* the player: two tiles in the bar could not hold a scrubber,
so the controls lived a hover away. The wide row (D82) put artwork, title, timeline and buttons on
the row itself, which made the popover a second copy of the same four things — and a hover between
you and the buttons you were looking at.

So it is gone, along with a panel, a 400 ms hover-out grace period, a re-layout on every track
change, a click monitor to dismiss it, and an anchor sentinel in `PanelController` for a row that is
not an application. Nothing opens when the pointer crosses the player now.

The one thing it held that the row cannot is a full, untruncated title, which is real on a compact
bar where the row is 64 points wide. That moved into the row's context menu as a disabled header —
right-click the player and it says what is playing. The group popover and the window flyout keep
their panels: those show things that genuinely do not fit in a bar.

## D89. The sound belongs to the application, not to the process making it.
YouTube in Chrome produced no media row at all, while Control Center showed it — the exact gap D75
predicted we would live with, except this one was ours.

The process CoreAudio names as sending audio out is not the browser. It is
`Google Chrome.app/…/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper`, a
renderer, and a helper is not an `NSRunningApplication`, so
`NSRunningApplication(processIdentifier:)` returns nil and `currentPlayers()` skipped it. Safari and
every Electron application have the same shape.

Two things do know who owns the sound, and both are checked before giving up: the helper's
executable lives inside the owning bundle, so the **outermost** `.app` on its path is the
application (`Google Chrome.app`, not `Google Chrome Helper.app`); and its parent process is usually
the application itself, which covers a helper stored outside the bundle. `launchd` as a parent means
no owner rather than "launchd is playing".

Once the player is named, everything downstream already worked: the row takes its title from the
application's window, and `MediaTitle.clean` strips both `YouTube` and `Google Chrome` off the end.
Verified with the row live: *"Đánh giá Nintendo Switch 2 sau hơn…"*, artist *Google Chrome*.

## D92. A browser's play state comes from its window title, because its audio never stops.
The row showed a pause button on a paused YouTube video. The reason is measured, not guessed: with
the video paused, `kAudioProcessPropertyIsRunningOutput` still reports Chrome's renderer as sending
output — the audio unit stays alive — so `!audioPlayers.isEmpty` says "playing" for as long as the
tab exists.

What does change is the window title. Chrome writes
`<video> - YouTube - Audio playing - Google Chrome - <profile>` while a tab makes sound and drops
`Audio playing` the moment it is paused. Nexus already reads that title for the track name, so the
play state now comes from the same read: the marker means playing, `Audio muted` also means playing
(the video runs, the volume does not), and the marker's *absence* means paused — but only for a
player that has published one before, or an application that never does would read as permanently
paused.

Order of evidence, most reliable first: a scriptable player's own answer (`player state is playing`),
then the window marker, then the sound itself. Chrome-family browsers publish the marker; Safari does
not, and falls back to the last rung.

## D95. A player that has quit is not paused.
The row deliberately survives a pause: a scriptable player that stops making sound still has the film
loaded, and a row that vanished on pause could not be unpaused (D83). Quitting is a different thing
that looks identical from inside — the audio stops, and nothing else arrives. Spotify and Music post
no notification when they quit, `MediaPositionService` only polls while somebody is looking at the
row, and CoreAudio has nothing to say about a process that no longer exists. So the last track sat
there with transport buttons that reached nobody.

The evidence that was missing is the plainest one available: whether the application is still
running. It arrives twice over — `.applicationTerminated` from the application monitor clears
whatever that bundle identifier owned, and `isActive` re-checks liveness for the published track and
for the paused-but-present player, so a row can never outlive its player even if the event is missed.

Not the cause of the report that prompted it: closing a browser *tab* was measured and already
clears the row (a YouTube tab, a `<video>` element and a WebAudio tone all stop CoreAudio's
`IsRunningOutput` within two seconds, and the row goes with them). What this fixes is the case one
step further out — the player itself going away.
