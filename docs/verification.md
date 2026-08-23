# Verification log

What has actually been checked against a running, installed Nexus — as opposed to what the tests
cover. Newest pass last. A row here is worth writing only if it says how it was checked, so a later
reader can repeat it or disbelieve it.

## Definition of Done (§33) — 2026-08-23

Against `/Applications/Nexus.app`, signed "Bugler Local Dev", one 1920×1080 display, 24 running
applications.

| §33 item | Result | How |
|---|---|---|
| Launch Nexus | Pass | `Nexus launched in 459 ms` from a cold start out of `/Applications`; the 1 s budget holds with the Accessibility grant already in place |
| See a vertical Dock/sidebar | Pass | Bar window present in `CGWindowListCopyWindowInfo`, `5 pinned, 19 running` |
| Pin, launch, see running applications, window counts | Pass | Shipped M2–M3 and re-read here from the accessibility tree: every row's value carries `running, N windows` |
| View application windows, activate one | Pass | Window flyout, and `AXPress` on a window row performs the activation (D88) |
| Press the shortcut, search applications / windows / files, run an action | Pass | `⌥Space` opened the palette; `nexus` returned a Windows result (`Code — DECISIONS.md — Nexus`), file results and actions in one merge |
| Configure the sidebar | Pass | Settings panes, live-applied; exercised through this session's own toggles |
| Restart and retain configuration | Pass | `defaults export` before and after a restart: the stored JSON is byte-identical, version 4 |
| Use Nexus across multiple displays | Partly, see below | Verified on two 2560×1440 displays after M20; disconnect and reconnect still needs a hand at the cable |
| Use Nexus comfortably with keyboard navigation | Pass, after a fix | The palette was already keyboard-first. The bar was not reachable at all by VoiceOver: `AXPress` returned success and did nothing, because no row in a panel that cannot become key is a SwiftUI `Button`. Fixed in D88 and re-checked — pressing the launcher opens the start menu, pressing Search opens the palette, and every bar row and palette result now lists `AXPress` |

### Accessibility detail

Read back with an `AXUIElement` walk of the live process rather than by launching VoiceOver, which
would have talked over the user's session. What the tree shows:

- Every interactive element is an `AXButton` with a label, a value carrying its state
  (`running, 3 windows`, `Application · running`, `minimized`), and a hint saying what pressing does.
- The palette exposes its field (`AXTextField`, labelled by its placeholder), the scope chip
  (`AXMenuButton`, value = the current scope) and `AXHeading` per category.
- Each panel names itself: `Nexus`, `Nexus Search`, `Nexus windows`, `Nexus group`,
  `Nexus start menu`.
- Three defects found and fixed in the same pass: no press action anywhere (D88), no window titles,
  and "running, 1 windows".

### 30-minute leak soak

Sampled every 30 s for 60 samples while the palette was opened, searched and closed on each sample.

| | Start | End | Shape |
|---|---|---|---|
| Resident memory | 137.5 MB | 142.4 MB | +4.9 MB, almost all of it in the first ten minutes; the last ten average +32 KB/min |
| Open descriptors | 347 | 396 | Flat from minute 11 onwards; the growth is `iconservices.store` mappings, and `IconCache` is bounded at 256 objects / 16 MB |
| Threads | 4 | 4 | 4–6 throughout |

`leaks` on the same process: **288 leaks, 14,400 bytes**, every attributed stack in Apple's own
frameworks — `AppIntents`' `LNProcessInstanceRegistryClient makeXPCConnection` and Foundation's XPC
bookkeeping. No Nexus frame appears in any of them. The process is signed as restricted, so `leaks`
reports it as "not debuggable" and its symbolication of our frames is limited; the number is a floor,
not a proof.

Read as: no unbounded growth — the slope decays by two orders of magnitude over the run and the
descriptor count stops moving — but not a flat line either. The residual 32 KB/min is worth
re-measuring after a change to the search path.



## Two monitors — 2026-08-23, after M20

Displays: 0 (menu bar) 2560×1440 @2x at the origin, 1 the same to its right. Bottom bar, Dock
Replacement Mode on.

| Check | Result |
|---|---|
| One bar, "Main display" | Bar stays on display 0; the Settings window on display 1 does not drag it across |
| "Display with the pointer" | Pointer moved to display 1 → bar reframed to x 2583 within a second; back to display 0 → x 23. Log: `Pointer moved to another display; the bar follows` |
| "Every display" | Two panels, `23,-22 2513x94` on display 0 and `2583,-22 2513x94` on display 1, both drawing the full bar — start menu, pinned, running, media player with the live YouTube title, Trash and the search box |
| Reserved Space, per display | Unit-tested: a window over display 1's bar is pushed to x 1512 and stays on display 1; a window clear of both is untouched; one sweep clears both. Live: found and fixed a bug where a bar paired with the wrong screen pushed the Settings window onto the other monitor |
| Disconnect / reconnect | **Still not verified** — needs someone to pull the cable. The logic has tests; the hardware pass does not |

Note on reading window geometry with two displays: `CGWindowListCopyWindowInfo` bounds include the
panel's shadow, so a bar 8 pt above the screen edge reads as hanging 22 pt below it. The window's own
frame is the truth — `{23, 8, 2513, 64}` for the numbers above.

## After the two-monitor session — 2026-08-23

| Check | Result |
|---|---|
| Closing Settings keeps both bars | Fixed and re-checked: bars still at `23,8` and `2583,8` after the window closes, focus back to Chrome, and the accessibility tree still lists 60 buttons (D93) |
| A paused browser shows a play triangle | Measured first: paused, CoreAudio still reports Chrome's renderer as outputting, while the window title drops `Audio playing`. After the fix the button reads Play when paused and Pause when playing, on both bars (D92) |
| The bar's Search part | Both styles live: an icon in one slot, or the box across three that opens the palette beside it |

## Milestones 21 and the two fixes before it — 2026-08-23, 17:00

One 1920×1080 display by then; the two 2560×1440 monitors of the earlier session were gone.

| Check | Result |
|---|---|
| The menu-bar item says which way it toggles | Driven through the accessibility tree: the item read `Hide Nexus Bar`, clicking it took the bar off screen, reopening the menu read `Show Nexus Bar`, and clicking that put the bar back (D94) |
| A quit player loses its media row | VLC playing a generated WAV: row showed `long` with a 0:34 / −0:53 timeline. `quit` VLC → the row was gone within three seconds (D95) |
| Closing a browser tab clears the row | Measured *before* fixing anything, since that was the report. A YouTube video, an `<audio>` element and a WebAudio tone, each closed as the only tab, as one tab of several, while playing and while paused: CoreAudio stopped naming Chrome within two seconds every time, and the row went with it. The reported symptom did not reproduce on this build |
| Configuration migrates 4 → 5 | `defaults export` after installing M21: `version: 5`, the five pinned applications unchanged, no new `configuration.corrupt.*` key (D96) |
| Nexus starts on the new build | `Nexus launched in 924 ms`, `Sidebar panels shown: 1`, `Sidebar rows: 5 pinned, 17 running` |
| Dragging a folder from Finder onto the bar | **Not verified.** The machine's displays changed mid-session, `screencapture` began returning wallpaper with no windows and System Events lost Finder — the signature of Screen Recording and Accessibility being toggled in System Settings, which was frontmost. Driving synthetic drags through that would have proved nothing. The drop handler, the listing, the refusal and the missing-folder cases are unit-tested; the Finder drag itself is the one part of M21 with no live pass |

## Milestone 22 — 2026-08-23, 17:2x

**No live pass.** By this point `screencapture` returned the desktop picture with no windows and an
`AXUIElement` walk of Nexus returned nothing but the application element repeated — both of which
mean the grants those tools need were off. The build installs and runs; the section, its cap, its
ordering, the setting and the restore path are unit-tested (8 tests). What has not been seen is a
real window being minimized and a row appearing for it. That, and M21's Finder drag, are the two
things to check first in the next session with the permissions back.

## Milestone 23, and what the machine would and would not answer — 2026-08-23, 18:10

| Check | Result |
|---|---|
| Both hotkeys register on the real machine | Pass, from the log of the installed build: `Global shortcut registered for search (key 49, modifiers 2048)` and `Global shortcut registered for focusBar (key 99, modifiers 4096)`. So `⌃F3` is not owned by anything else here, and the per-slot registration works outside the tests |
| The build starts clean with everything of M21–M23 in it | Pass: `Nexus launched in 994 ms`, `Sidebar rows: 5 pinned, 17 running` |
| System Settings panes are real | Pass, in the test suite rather than by hand: the suite reads `/System/Library/ExtensionKit/Extensions` on the machine it runs on and requires Displays and Keyboard to be among the panes it finds |
| Keyboard mode end to end, the Finder drag (M21), minimising a window (M22) | **Not verified.** `screencapture` returns the desktop picture with no windows, an `AXUIElement` walk of Nexus returns only the application element, and Nexus publishes no AX windows at all — the signature of a locked or screen-savered Mac, with System Settings frontmost since 17:00. Driving synthetic keys and drags into that would prove nothing |

The three pending checks, for whoever is next at the keyboard:

1. Drag a folder onto the bar and click it (M21).
2. Minimise a window and look before the Trash; click the row to restore it (M22).
3. Press `⌃F3`, walk with the arrows, press Return, then press Escape and type into whatever was
   in front — no click in between (M23).

## The three pending checks, run — 2026-08-23, 18:45

Two 2560×1440 displays, bar on both, driven with synthetic events against the installed build.
Every one of them found something.

| Check | Result |
|---|---|
| M21, dragging a folder from Finder onto the bar | **Failed, fixed, passed.** `~/Desktop/NexusStackTest` dragged onto the bar did nothing: the drop was SwiftUI's and the AppKit row overlays sit on top of it, so a drop over a row never reached it. With an AppKit drop target on the bar's hosting view: `Pinned folder /Users/cong.bui/Desktop/NexusStackTest`, `Dropped 1 file(s) on the bar: pinned` |
| M21, opening the stack | Pass: the popover reads `NexusStackTest · 3 items` with Subfolder, alpha.txt and beta.txt on the grid |
| M22, minimising a window | **Failed, fixed, passed.** Minimising a Finder window took the window *out* of Nexus's enumeration — `Windows: 9 total, 0 minimized` became `8 total, 0 minimized` — because a minimized window's subrole changes to `AXDialog` (D100). After the fix: `9 total, 1 minimized`, and the row appears before the Trash |
| M22, restoring | Pass: clicking the row unminimised the window (`collapsed` false for every Finder window) and the count went back to `0 minimized` |
| M23, the shortcut | **Failed, fixed, passed.** `⌃F3` registered and never fired — macOS owns it. `⌃⌥Space` registers (`modifiers 6144`) and works |
| M23, the keys | **Failed, fixed, passed.** Arrows did nothing: `keyDown` on the hosting view never runs, because SwiftUI's own subview is first responder. Handled on the panel now — `→` moves the ring from the launcher to Finder, Escape clears it and hands focus back to Finder (D101) |
| Group popover title | Not a bug: the popover draws its name. The group was *called* "Group", because Chrome and Brave declare no `LSApplicationCategoryType` at all. Groups with nothing in common are now named after their members |
| Popovers on the right display | Found while testing the above: clicking a group on the second monitor opened its popover on the first, because every popover anchored to `bars.first`. They anchor to the bar under the pointer now |

Method note: `screencapture -R` for the bar strips, System Events for the accessibility answers
(`minimized=true subrole=AXDialog` is what named D100), `log show` for Nexus's own trail, and
synthetic CGEvents for the drag, the clicks and the keys.

## The four asks from the bottom-edge round — 2026-08-23, 19:10

| Check | Result |
|---|---|
| The bar's bottom edge | Before: a 64 pt icon in a 64 pt bar, feet and running dots clipped by the screen edge. After: icons whole, a dot visible under each one, and the bar sits the same 8 pt off the edge — it is the bar that grew, not the gap (D102) |
| Rename from the second monitor | Before: popover on display 1, alert on display 0. After: alert at x 3710 for a click on display 1, x 1150 for a click on display 0 — read back from the accessibility tree, not by eye |
| The group popover | Title reads as a title and carries a pencil; hovering a member shows the minus badge. Both verified on the real popover at 2× |
| Settings | 620 × 790, resizable, eight tabs. Dock holds where the bar is, Bar what it shows, Appearance how it looks. About shows `Version 0.1.0 (1)`, author, licence and `/Applications` |
| `make dmg` | `build/Nexus-0.1.0.dmg`, 3.2 MB, mounts as `Nexus 0.1.0` with `Nexus.app` and the `Applications` shortcut inside |
