# Nexus

**The command center for your Mac.**

A native macOS vertical dock and a unified search palette in one agent application. Nexus runs
in the menu bar, never takes focus away from what you are typing in, and never changes a single
system setting on your behalf.

> Status: MVP (Milestones 1–7 complete). Local builds only — see [Installation](#installation).

---

## Why it exists

The Dock is horizontal, wastes vertical space on wide displays, and knows nothing about your
windows. Spotlight searches files well and applications passably, and cannot raise a window.
Nexus is one surface for applications, their windows, files, and a small set of actions —
built the way a macOS utility should be: native, event-driven, local, and quiet.

## Features

| | |
|---|---|
| **Sidebar on any edge** | Left, right, top or bottom, configurable width, icon size, spacing, corner radius and opacity. Auto-hide with an edge-hover reveal, or always visible. |
| **Applications** | Pin, unpin, reorder by dragging one icon onto another, launch, activate, quit and force quit. Running indicator and per-app window count. |
| **Windows** | An application's windows are in its context menu, frontmost ticked. Hovering an icon opens a flyout with live titles and optional thumbnails; **Show All Windows** opens the same flyout from the menu. *(Accessibility)* |
| **Trash** | Always in the bar, before Search, with the macOS Trash icon showing full or empty. Click opens it; the context menu empties it, after asking. |
| **Start menu** | Optional launcher button and a browsable grid of everything installed, with a filter field and Sleep / Restart / Shut Down / Log Out. Off by default. |
| **Media player** | Optional: artwork, track name, ⏮ ⏯ ⏭ and a draggable timeline, all in the bar — nothing to hover, nothing to open. *(Timeline for Music, Spotify and VLC.)* |
| **Now playing** | Optional: the track and transport controls in the bar, for any player — Music and Spotify publish theirs, and everything else is named by its window. *(Accessibility for the latter)* |
| **Always in reach** | Trash and Search sit in a zone that never scrolls. The applications between them fill the edge — as many rows as the screen holds — and scroll only once it is full. |
| **Groups** | Drag one icon onto another and hold to make a folder. Auto-named from the applications' own category, renameable, 9 or 16 per group. |
| **Minimized windows** | The windows you minimise get rows of their own before the Trash — newest first, at most three — and a click puts one back. *(Accessibility)* |
| **Folder stacks** | Drag a folder from Finder onto the bar. Clicking it shows what is inside on a grid — folders first, a file opens in its own application, a subfolder opens in Finder. |
| **Reserved space** | Optional: windows that overlap the bar are moved off it, full-screen windows left alone. *(Accessibility)* |
| **Search** | A command palette on a global shortcut, centred like Spotlight — or opened from a search box in the bar, beside it. Applications, windows, files and actions, ranked by match quality, provider weight and frecency, with one scope filter — `⌃1`…`⌃6` or `⇥` — for applications, files, folders, or System Settings panes and actions. |
| **Dock replacement** | Optional: the macOS Dock hides while Nexus runs and comes back when it quits. Your Dock settings are saved first and restored exactly. |
| **Settings** | General, Dock, Appearance, Behavior, Search, Permissions. Everything applies live. |
| **Onboarding** | Six skippable steps. Skipping all of them still leaves a working launcher. |
| **Accessible** | VoiceOver labels on every element, Reduce Motion and Increase Contrast honoured. |

### Screenshots

_Placeholder — add `docs/images/sidebar.png`, `docs/images/search.png`, `docs/images/settings.png`._

## Permissions

Nexus never asks for a permission at launch, never re-asks after a refusal, and never blocks a
feature behind a permission it does not need.

| Permission | Needed for | Without it |
|---|---|---|
| *(none)* | Sidebar, pinning, launching, quitting, window **counts**, application search, file search, actions | — |
| **Accessibility** | Window lists, window titles, raising a window, window search | Everything above still works |
| **Screen Recording** *(optional)* | Window thumbnails | Title-only window lists |

## Installation

There is no notarized release. Build it yourself:

```sh
git clone <this repository>
cd Nexus
make run
```

`make run` builds `build/Nexus.app`, signs it, and launches it — that is the development loop.
To keep Nexus:

```sh
make install
```

That puts the signed bundle in `/Applications` and launches it from there. Do this before turning
on **Launch Nexus at login**: macOS registers the login item at the path the application is running
from, so a login item registered out of `build/` breaks the moment you `make clean` (D86). The
Settings toggle says as much when Nexus is running from anywhere else.

Uninstalling is the usual drag to the Trash; macOS drops the login item with it.

**Signing matters.** macOS ties Accessibility and Screen Recording grants to the code
signature. An ad-hoc signature changes on **every rebuild**, so every permission you grant is
reset the next time you build — and because TCC's record no longer matches the running binary,
`AXIsProcessTrusted()` keeps returning false however many times you flip the switch.

`make` picks an identity automatically: an "Apple Development" certificate if you have one, else
**any** valid codesigning identity in your keychain, else ad-hoc with a warning. Any stable
certificate works — TCC cares that the signature does not change, not who issued it.

```sh
make signing-info                                  # shows what will be used
make app SIGNING_IDENTITY="My Local Dev"           # or pick one explicitly
```

If it reports `-`, create a certificate once: **Keychain Access → Certificate Assistant →
Create a Certificate…**, type *Code Signing*; or add a free Apple Development certificate in
Xcode → Settings → Accounts → Manage Certificates.

If Accessibility still reads as denied right after you grant it, use **Restart Nexus** on the
permission screen — macOS only hands out that permission when a process starts.

### Dock Replacement Mode

Off by default. Turn it on in **Settings → Dock** (or during setup) and Nexus hides the macOS
Dock while it runs: auto-hide on, a ~17-minute reveal delay so the Dock never slides in by
accident, and the Dock parked on the edge Nexus is not using.

Nothing is removed or patched. `Dock.app` keeps running, Mission Control and Spaces are
untouched, and SIP stays on. Only four preferences change:

```
autohide  autohide-delay  autohide-time-modifier  orientation
```

Your values are captured before the first change and put back exactly — a key you never set is
deleted on restore rather than written back with a plausible default.

**The Dock comes back whenever Nexus is not running.** Quitting restores it, launching applies it
again. That is also the uninstall story: quit Nexus, then delete it, and the Dock is already
normal.

If Nexus is killed outright (`SIGKILL`, a panic) no restore runs. Any of these fixes it:

- Start Nexus again — it notices and restores on launch.
- **Restore macOS Dock** in Settings → Dock, or in the menu-bar menu.
- `⌥⌘D`, which macOS handles itself and Nexus never touches.
- Or by hand:
  ```sh
  defaults delete com.apple.dock autohide-delay
  defaults delete com.apple.dock autohide-time-modifier
  defaults write com.apple.dock autohide -bool false
  killall Dock
  ```

## Development

```sh
swift build          # build the libraries and the executable
swift test           # run the unit tests
make lint            # rebuild from scratch and fail on any warning
make app             # assemble and sign build/Nexus.app
make run             # stop any running instance, rebuild, relaunch
make install         # copy the signed bundle to /Applications and run it from there
make signing-info    # show which identity will be used
make clean
```

No `.xcodeproj` is checked in (D1) and there are no third-party dependencies. Requires
macOS 14+ and a Swift 6 toolchain.

Logs. Everything worth diagnosing is logged at `.notice` or `.error`, which macOS persists;
`.info` and `.debug` are memory-only and are not used for state changes.

```sh
make logs        # persisted log, last 30 minutes
```

`log` is a **shell builtin** in some shells (zsh included) and shadows `/usr/bin/log`, which
makes `log show …` fail with `too many arguments` or return nothing. Use `make logs`, or the
absolute path:

```sh
/usr/bin/log show   --predicate 'subsystem == "com.congbui.nexus"' --last 30m --style compact
/usr/bin/log stream --predicate 'subsystem == "com.congbui.nexus"' --level debug --style compact
```

Configuration is versioned JSON in `UserDefaults`:

```sh
defaults export com.congbui.nexus -   # readable dump
make reset-config                     # wipe settings; next launch runs onboarding
```

## Measured performance

Measured on an Apple silicon Mac running macOS 26.6, with 454 applications indexed.

| Metric | Budget | Measured |
|---|---|---|
| Cold start (process exec → sidebar on screen) | < 1 s | 702–753 ms warm; ~1.3 s on the first launch after a build |
| Idle CPU | ~0 % | 0.00 s of CPU over 45 s idle |
| CPU under churn | — | 0.90 s over 150 s while 60 applications launched and quit |
| Resident memory | bounded | 60.1 MB → 60.5 MB over the same churn: flat |
| Application + window search | < 50 ms | under 50 ms over 454 applications and 200 windows (asserted in the test suite) |

Reproduce the search budget with `swift test --filter SearchIntegrationTests`.

## Architecture

```
Package.swift
├── NexusCore   models · configuration · events · logging · applications · windows · search · system
├── NexusUI     panels (AppKit) · sidebar · search palette · settings · onboarding · permissions
└── NexusApp    NSApplicationDelegate · composition root · menu-bar status item
```

- **Views own no system logic.** View → ViewModel (`@MainActor @Observable`) → service protocol → macOS API.
- **Services are actors.** Accessibility calls are synchronous IPC into other processes and must
  never run on the main thread.
- **Events, not polling.** Every update comes from `NSWorkspace`, an `AXObserver`, or a screen-
  parameters notification. There is exactly one poll in the whole app: permission status at 1 Hz
  while a permission screen is on screen, because macOS publishes no TCC notification.
- **Swift 6 strict concurrency**, zero build warnings.

Full detail: [`ARCHITECTURE.md`](ARCHITECTURE.md) and [`docs/`](docs/README.md) — the design
documents in [`docs/design/`](docs/design), one per feature, and the decision log in
[`docs/decisions.md`](docs/decisions.md).

## Roadmap

Milestones 1–7 in [`ROADMAP.md`](ROADMAP.md) are complete. Everything beyond the MVP —
workspaces, widgets, plugins, automation, AI — is described in the foundation document and
deliberately **not** built. The architecture leaves three seams open for it: `SearchProvider`,
`NexusActionDescriptor`, and configuration versioning.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT — see [`LICENSE`](LICENSE).
