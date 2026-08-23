# Contributing to Nexus

## Getting set up

```sh
swift build && swift test
make run
```

macOS 14+ and a Swift 6 toolchain. No `.xcodeproj`, no package dependencies. If you add a
dependency, the pull request has to say what it does that a few lines of Foundation or AppKit
cannot (§63).

## The bar for a change

- `make lint` passes. **Zero warnings** is the gate, not a preference.
- `swift test` passes.

  If it fails in ways that make no sense — a value read from a struct you did not touch, tests that
  pass one run and fail the next — and you have just added or removed a *stored property* on a type
  in `NexusCore`, the incremental build is stale: the dependent modules were not recompiled and are
  reading the old field offsets. `rm -rf .build && swift test` settles it. Verified the hard way
  while deleting one unused property.
- New non-trivial logic comes with a test. Pure logic — ranking, matching, layout, configuration
  — is where the tests live; no test touches the real Accessibility API or launches applications.

## House rules

These are load-bearing, not style preferences:

1. **Never steal focus.** The sidebar panel can never become key or main. If a change makes a
   click on the sidebar move the frontmost application, it is a bug, however good it looks.
2. **No polling.** Every update is an event: `NSWorkspace` notifications, `AXObserver`,
   `didChangeScreenParameters`. The one sanctioned exception is permission status at 1 Hz while
   a permission screen is visible, and it is cancelled on dismiss.
3. **Views own no system logic.** A SwiftUI file that imports `ApplicationServices` or
   `ScreenCaptureKit` is a bug. View → ViewModel → service protocol → macOS API.
4. **Accessibility calls never run on the main thread.** They are synchronous IPC into another
   process and block for as long as that process is unresponsive. Every element gets a 250 ms
   messaging timeout.
5. **Degrade, never fail.** A missing permission, a vanished window, a disconnected display and
   an unresponsive application are all normal states with a designed appearance. No alerts for
   things the user did not just do.
6. **Nexus changes no system settings.** Not the Dock, not Spotlight's shortcut. It explains and
   deep-links; the user decides.
7. **No shell, no AppleScript, no `osascript`.** Those need Automation permission and belong to
   an automation engine that is out of scope.
8. **Accessibility labels are written with the view**, not retrofitted. Every interactive element
   needs a label, a value where it has state, and a hint.
9. **Localised strings.** User-facing text goes through `String(localized:)` from the start.
10. **Privacy in logs.** File paths, window titles and search queries are `.private`. Bundle
    identifiers, counts and error codes are `.public`. Never log file contents or tokens.

## Testing against a real machine

Never write to the `com.congbui.nexus` defaults domain from a script — that is the product's
real configuration, and leaving debug values behind produces bug reports against code that is
working correctly (D45). Use `InMemoryConfigurationStore` in tests, and `make reset-config` to
put a machine back to a clean first-run state.

`log` is a shell builtin in zsh and shadows `/usr/bin/log`. Use `make logs`.

## Deciding things

If a technical choice is ambiguous, take the simplest native macOS option that preserves
extensibility, write it down in the area file under [`docs/decisions/`](docs/decisions/) — foundation, bar, windows, search, media or system — with the next free number and a row in the [`docs/decisions.md`](docs/decisions.md) index, in the existing format
(**decision — reason — alternative rejected**), and move on. Do not open a design discussion for
a one-line call.

## Scope

[`FEATURES.md`](FEATURES.md) is the scope. Sections 36–110 of the foundation document describe a
long-term vision that is deliberately **not** built. The architecture must not block it; it must
not contain it. No plugin loader, no widget host, no rule engine, and no abstraction with one
implementation waiting for a second.

## Commits

One milestone or one coherent change per commit. Explain what changed and why in the body;
reference the decision number when a commit implements one.
