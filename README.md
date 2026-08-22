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
| **Vertical sidebar** | Left or right, configurable width, icon size, spacing, corner radius and opacity. Auto-hide with an edge-hover reveal, or always visible. |
| **Applications** | Pin, unpin, reorder by drag, launch, activate, quit and force quit. Running indicator and per-app window count. |
| **Windows** | Flyout listing an application's windows with live titles; click one to raise it. Optional thumbnails. *(Accessibility)* |
| **Search** | A command palette on a global shortcut. Applications, windows, files and actions, ranked by match quality, provider weight and frecency. |
| **Settings** | General, Appearance, Behavior, Search, Permissions. Everything applies live. |
| **Onboarding** | Five skippable steps. Skipping all of them still leaves a working launcher. |
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

`make run` builds `build/Nexus.app`, signs it, and launches it.

**Signing matters.** macOS ties Accessibility and Screen Recording grants to the code
signature. `make` prefers an "Apple Development" certificate from your keychain and falls back
to ad-hoc signing — and an ad-hoc signature changes on **every rebuild**, so every permission
you grant is reset the next time you build. Before you grant anything:

1. Open Xcode → Settings → Accounts, sign in with a free Apple ID, and **Manage Certificates →
   + → Apple Development**.
2. `make signing-info` should then name that certificate instead of `-`.

Or point it at any stable identity you already have:

```sh
make app SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)"
```

### Hiding the real Dock

Nexus never touches your Dock settings. If you want the Dock out of the way, do it yourself:
System Settings → Desktop & Dock → **Automatically hide and show the Dock**.

## Development

```sh
swift build          # build the libraries and the executable
swift test           # run the unit tests
make lint            # rebuild from scratch and fail on any warning
make app             # assemble and sign build/Nexus.app
make run             # stop any running instance, rebuild, relaunch
make signing-info    # show which identity will be used
make clean
```

No `.xcodeproj` is checked in (D1) and there are no third-party dependencies. Requires
macOS 14+ and a Swift 6 toolchain.

Logs:

```sh
log stream --predicate 'subsystem == "com.congbui.nexus"' --level debug --style compact
```

Configuration is versioned JSON in `UserDefaults`:

```sh
defaults read com.congbui.nexus configuration
```

## Measured performance

Measured on an Apple silicon Mac running macOS 26.6, with 454 applications indexed.

| Metric | Budget | Measured |
|---|---|---|
| Cold start (process exec → sidebar on screen) | < 1 s | 702–753 ms warm; 1299 ms on the first launch after a build |
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

Full detail: [`ARCHITECTURE.md`](ARCHITECTURE.md), [`docs/DESIGN_MVP.md`](docs/DESIGN_MVP.md),
[`docs/DECISIONS.md`](docs/DECISIONS.md).

## Roadmap

Milestones 1–7 in [`ROADMAP.md`](ROADMAP.md) are complete. Everything beyond the MVP —
workspaces, widgets, plugins, automation, AI — is described in the foundation document and
deliberately **not** built. The architecture leaves three seams open for it: `SearchProvider`,
`NexusActionDescriptor`, and configuration versioning.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT — see [`LICENSE`](LICENSE).
