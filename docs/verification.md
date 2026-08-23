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
| Use Nexus across multiple displays | **Not verified** | One display attached, and `CGDisplayCopyAllDisplayModes` reports a single mode, so there is nothing to unplug and no resolution to change. The logic has tests — UUID identity, identity round trip, a disconnected preference falling back to the menu-bar screen, and a preference that is never rewritten on resolve — but the hardware pass needs a second monitor |
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

