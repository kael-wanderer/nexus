# Decisions — The system around Nexus

Permissions, displays, and the macOS Dock Nexus replaces.

Part of the decision log; the index, and the rule these follow, are in
[`../decisions.md`](../decisions.md). Numbers are global and never reused, so the gaps
here are entries that live in another file, and the date each was made is in `git log`.

## D11. Displays are identified by `CGDisplayCreateUUIDFromDisplayID`, not `CGDirectDisplayID`.
Display IDs change across disconnect/reconnect; UUIDs do not.

## D13. Exactly one poll exists in the app: permission status at 1 Hz while a permission screen
is visible.
macOS publishes no TCC change notification and §111.6 requires a live checkmark.
Scoped to a visible screen and cancelled on dismiss.

## D14. Nexus never modifies the user's Dock settings.
Silently changing a system setting is the intrusiveness §4 rules out. The README tells users how
to auto-hide the Dock themselves.

## D32. Settings and onboarding are ordinary titled `NSWindow`s, and Nexus activates itself to
show them.
These two are the only surfaces that *should* take focus, and standard AppKit
controls (sliders, pickers, steppers) only render in their active appearance in a key window —
which is exactly why the sidebar and the flyout avoid them. `AuxiliaryWindowController` calls
`NSApp.activate()` on show and `NSApp.hide(nil)` on close, so an `.accessory` app never sits
"active" with nothing visible.

## D42. The grant screen offers a restart once the user has been to System Settings.
macOS hands a process its Accessibility trust at launch and does not reliably refresh it for an
already-running process, so "granted in TCC but not effective here" is a real state with no
public API to detect it. Rather than guess at TCC's contents, the screen offers the remedy: after
the user has opened System Settings at least once, an "already switched it on?" note appears with
a **Restart Nexus** button. `AppRelaunch` opens a replacement instance carrying a
`NEXUS_RELAUNCHING` environment marker and then terminates; the marker makes the replacement's
single-instance guard wait for the outgoing process to exit instead of deferring to it.

## D49. The frontmost application is seeded at monitor start.
`ApplicationService.activeBundleIdentifier` was only ever set by
`didActivateApplicationNotification`, so on a fresh launch no sidebar row showed as active until
the user switched applications once. `ApplicationMonitor.start()` now seeds it from
`NSWorkspace.shared.frontmostApplication`.

## D50. `.main` resolves to the menu-bar display, not `NSScreen.main`.
Caught live while verifying D46: on a two-display setup the sidebar jumped to the second
monitor (x = 2568) because the onboarding window had opened there. `NSScreen.main` is
documented as *"the screen containing the window with keyboard focus"*, so it follows Settings
or onboarding onto whichever monitor they land on and drags the sidebar along. `design/mvp.md`
§8 defines `.main` as "the display with the menu bar", which is `NSScreen.screens.first`.
Added `DisplayService.menuBarScreen` and routed `.main`, `.withMouse`'s fallback and the
disconnected-`.specific` fallback through it. Verified: sidebar stays at x = 8 with onboarding
open on the other display.

## D51. Dock Replacement Mode is `defaults` keys plus a Dock restart.
`autohide`, `autohide-delay` (1000 s), `autohide-time-modifier` and `orientation`, written with
`CFPreferences` and followed by terminating `com.apple.dock` — `killall Dock` without a shell,
since `launchd` brings it straight back. Rejected `NSApplicationPresentationHideDock`:
presentation options apply only while the owning application is active, and Nexus is an
`LSUIElement` that never activates, so the Dock would reappear the moment focus moved. Nothing
here touches `Dock.app`, system files or SIP — replace the Dock experience, not the Dock system
component.

## D52. Amends D14 ("Nexus never modifies the user's Dock settings").
It may, but only on explicit user action, only while running, and only after capturing a
snapshot in which every field is optional — a key that was never set is *deleted* on restore,
never written back as `false` or `0`. Dock-less exists only while Nexus runs: quitting restores,
launching re-applies, and a launch that finds `applied` set without `replacementEnabled` cleans
up after a run that was killed. That is also the uninstall story, since macOS gives an
application no uninstall hook. `⌥⌘D` is deliberately left alone as the escape hatch that needs
no Nexus at all.

## D54. The Dock is parked on the edge Nexus is not using.
Sharing an edge would put the Dock's hot zone under Nexus's own edge trigger, where every stray
mouse flick arms a 1000-second timer. The Dock has no top edge, so a top or bottom sidebar sends
it left rather than to the literal opposite.

## D91. A bar per display, or a bar that follows the pointer — the user picks.
Nexus drew one bar on one display, so a second monitor had no dock at all: every Space on it, in
Mission Control or out, showed nothing. `.withMouse` was supposed to cover that and did not — it
resolved "the display with the pointer" only when something *else* caused a reframe, so the bar
arrived on the other monitor minutes late, if ever.

Both behaviours are legitimate and they are not the same product. The native Dock moves; a Windows
taskbar is on every screen. So `appearance.display` gains `.everyDisplay` and the Settings picker
offers three: the menu-bar display, the display with the pointer, every display.

- **Following the pointer** needs to know the pointer crossed monitors, and macOS publishes no
  notification for that. A global `.mouseMoved` monitor is installed *only* in this mode; it compares
  two display identities and does nothing else, so the no-polling rule survives — this is an event,
  not a timer.
- **A bar per display** creates one panel per screen, all hosting the same model, so they show the
  same applications and the same media row. Panels are created and destroyed only when a display
  arrives or leaves; a reframe reuses them.
- **One row budget, sized to the smallest screen.** The zones (M14) are shared state, and a budget
  that fits the widest display would overflow the narrowest. Every bar therefore fits everywhere,
  at the cost of some slots on the larger screen.
- **Reserved Space now takes a list**, one geometry per bar, so a window is pushed off the bar on
  *its* display. Each geometry's screen is resolved from where the bar actually is, not from the
  preference's order: those disagree for a frame or two while a bar is moving between displays, and
  a bar paired with the wrong screen tells Reserved Space that every window on that screen is in the
  way. That bug pushed the Settings window onto the other monitor twice before it was caught.
- **Flyouts follow the pointer, not the primary bar.** A window list or a group popover anchors to
  whichever bar the pointer is on, so clicking an application on the second monitor does not open
  its windows on the first.

Not done: a per-display edge or width. `DisplayOverride` exists in the configuration and stays
unused — revealing one bar reveals them all, and they share one edge, because a second bar is for
reaching the same dock without crossing monitors.
