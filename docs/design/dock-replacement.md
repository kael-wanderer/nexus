# Milestone 8 — Dock Replacement Mode

Spec for review. Nothing here is implemented yet.

Two features that only make sense together: a sidebar that can sit on **any** screen edge, and a
mode that pushes Apple's Dock out of the way so Nexus can take its place.

---

## 1. Goals

- `SidebarPosition` gains `.top` and `.bottom`; all four edges are first-class.
- An optional **Dock Replacement Mode**: Apple's Dock becomes practically inaccessible while
  Nexus runs, and comes back the moment it stops.
- The user's original Dock configuration is preserved exactly and restored exactly.
- No system files touched, no `Dock.app` patching, no SIP changes, nothing that breaks on a
  macOS update. "Replace the Dock experience, not the Dock system component."

## 2. Non-goals

- Removing or disabling `Dock.app`. Mission Control, Exposé and Spaces keep working — they are
  Dock features, and Nexus does not replace them.
- Blocking the Dock's keyboard shortcuts (`⌥⌘D` still toggles auto-hide; that is the user's
  escape hatch, and taking it away would be hostile).
- Persisting Dock-less across a Nexus quit. Mode off ⇒ Dock back. See §5.

---

## 3. Four positions

### 3.1 Model

```swift
public enum SidebarPosition: String, Codable, Sendable, CaseIterable {
    case left, right, top, bottom

    /// Vertical edges stack rows top-to-bottom; horizontal edges lay them left-to-right.
    public var isVertical: Bool { self == .left || self == .right }
}
```

Existing configurations decode unchanged — the two new cases are additive, and `version` stays
`1`. No migration.

### 3.2 Layout math

`SidebarLayout` is pure and already unit-tested; the change is transposition, not new geometry.
Every function that says "height from rows, width from appearance" gets the mirrored branch:

| Function | Vertical (today) | Horizontal (new) |
|---|---|---|
| `size(sectionRowCounts:appearance:expanded:)` | width = `appearance.width`, height from rows | width from rows, height = `appearance.width` |
| `frame(size:in:position:hidden:)` | pinned to `minX` / `maxX - width`, centred on `midY` | pinned to `minY` / `maxY - height`, centred on `midX` |
| `rowCentreFromTop(…)` | distance from panel top | becomes `rowCentre(…)`, distance from panel **leading** edge; same arithmetic |
| `flyoutFrame(size:beside:anchor:…)` | beside the bar (left/right) | above the bar (bottom) or below it (top) |
| `edgeTriggerFrame(in:position:)` | 2 pt column, full height | 2 pt row, full width |

Clamping rule is unchanged, only the axis differs: the bar never exceeds
`visibleFrame.width - screenMargin * 2` horizontally, and content scrolls when it would.

### 3.3 View

`SidebarView` swaps its outer `VStack` for an `HStack` when `position.isVertical == false`, and
the `ScrollView` axis follows. Separators become vertical rules. Rows themselves are unchanged.

**Hover-expand is vertical-only** (decided): horizontal orientation shows icons only, no name
labels, because growing the bar's *height* on hover makes every window on screen jump. The
`hoverExpand` toggle stays in Settings but is inert while the position is top or bottom, and the
Settings row says so rather than silently doing nothing.

### 3.4 Menu-bar collision

At `.top` the menu bar owns the top ~25 pt. `visibleFrame` already excludes it, so the bar
lands directly beneath the menu bar with no special case. Worth one test asserting exactly that,
since it is the one place where `frame` vs `visibleFrame` would silently look almost right.

---

## 4. `DockControlService`

New file, `Sources/NexusCore/System/DockControlService.swift`. It owns every read and write of
the `com.apple.dock` domain — nothing else in the codebase touches it.

### 4.1 The three keys

```
autohide               true      # Dock hides
autohide-delay         1000.0    # ~17 minutes of hovering before it peeks: practically unreachable
autohide-time-modifier 0.0       # if it ever does appear, no animation to sit through
```

Plus one more, which is what makes the mode usable rather than merely quiet:

```
orientation            <edge opposite Nexus>
```

If Nexus sits at the bottom and the Dock's hot edge is also the bottom, every downward flick of
the mouse arms a 1000-second timer under Nexus's own edge trigger. Parking the Dock on the
opposite edge removes the overlap entirely.

### 4.2 Writing

`CFPreferencesSetAppValue` / `CFPreferencesAppSynchronize` against `com.apple.dock`, then
restart the Dock by terminating it:

```swift
NSRunningApplication
    .runningApplications(withBundleIdentifier: "com.apple.dock")
    .first?
    .terminate()
```

`launchd` relaunches it (`KeepAlive`), which is what `killall Dock` amounts to — without
spawning a shell. Preferences are read by the Dock at start-up, so the restart is not optional.

### 4.3 Preserving the original

```swift
public struct DockSnapshot: Codable, Sendable, Equatable {
    public var autohide: Bool?
    public var autohideDelay: Double?
    public var autohideTimeModifier: Double?
    public var orientation: String?
    public var capturedAt: Date
}
```

Every field is **optional on purpose**: a key that was never set must be *deleted* on restore,
not written back as `false` / `0`. Writing a value the user never had is a silent config change,
and it is the difference between "restored" and "close enough".

The snapshot lives in `NexusConfiguration.dock` and is captured exactly once, at the transition
off→on. Re-enabling while already enabled must not overwrite it with Nexus's own values.

### 4.4 API

```swift
public protocol DockControlling: Sendable {
    func snapshot() -> DockSnapshot                 // read current state
    func apply(sidebarPosition: SidebarPosition)    // write the four keys, restart Dock
    func restore(_ snapshot: DockSnapshot)          // write back or delete, restart Dock
    var isDockHidden: Bool { get }                  // for the status indicator
}
```

A protocol because the tests need a fake — no test may write to the real `com.apple.dock`
domain, the same rule that already applies to `com.congbui.nexus`.

---

## 5. Lifecycle and safety

The rule: **Dock-less exists only while Nexus runs.**

| Event | Behaviour |
|---|---|
| Toggle on | Capture snapshot → apply → set `dock.replacementEnabled = true`, `dock.applied = true` |
| Toggle off | Restore snapshot → `applied = false`, `replacementEnabled = false` |
| Nexus quits (`applicationWillTerminate`) | Restore snapshot → `applied = false`; `replacementEnabled` stays true |
| Nexus launches with `replacementEnabled = true` | Apply again |
| Nexus launches with `applied = true` but `replacementEnabled = false` | Previous run died before restoring → restore now |
| Uninstall | Nothing to do: the app was quit first, so the Dock is already back |

That last row is why restore-on-quit is the design and not a nicety — macOS gives an app no
uninstall hook, so the only reliable uninstall story is "the Dock is normal whenever Nexus is
not running".

**`SIGKILL` / kernel panic** runs no handler, so the Dock stays hidden until Nexus next starts.
Three cheap layers cover it:

1. The launch check above restores automatically on the next run.
2. Settings keeps a **Restore macOS Dock** button, enabled at all times, independent of the
   toggle's state.
3. README documents the escape hatch, for the case where Nexus itself will not start:
   ```
   defaults delete com.apple.dock autohide-delay
   defaults delete com.apple.dock autohide-time-modifier
   defaults write com.apple.dock autohide -bool false
   killall Dock
   ```

Also: `⌥⌘D` is left alone deliberately, so a stuck user always has a keystroke that brings the
Dock back without knowing any of this.

---

## 6. Configuration

```swift
public struct DockConfiguration: Codable, Sendable, Equatable {
    public var replacementEnabled = false
    public var applied = false
    public var snapshot: DockSnapshot?
}
```

Added to `NexusConfiguration` as `dock`. Defaults are off, so an existing config file decodes to
"Dock Replacement Mode off" with no migration.

---

## 7. UI

### 7.1 Settings — new "Dock" pane

```
Dock Replacement

  ◉ Nexus is my Dock     ○ Nexus is a sidebar
      Hides the macOS Dock while Nexus is running and restores it when Nexus quits.

  Position   ( ) Left  ( ) Right  ( ) Top  (•) Bottom

  ☑ Launch Nexus at Login

  macOS Dock: Hidden by Nexus            [ Restore macOS Dock ]
```

- Position moves here from Appearance (it is the same setting, shown where it now matters);
  Appearance keeps width, icon size, spacing, opacity, corner radius.
- Launch at Login is the existing `LoginItemService` toggle, mirrored here because a Dock
  replacement that is not running is not a Dock replacement.
- The status line reads live from `DockControlling.isDockHidden`, so it tells the truth even if
  the user changed the Dock behind Nexus's back.

### 7.2 Onboarding — one new step

`OnboardingViewModel.Step` gains `.dock`, between `.sidebar` and `.done`: position picker (four
edges, live preview via the real sidebar) plus the "Use Nexus as primary Dock" checkbox,
defaulting **off**. Skipping leaves the Dock untouched — the §111.6 rule that skipping everything
still yields a working launcher.

### 7.3 Status item

The menu gains a disabled first row, `macOS Dock: Hidden` / `macOS Dock: Visible`, and a
**Restore macOS Dock** item that appears only while `applied` is true. The menu bar is the one
piece of chrome an `LSUIElement` app always has, which makes it the right place for the
"something is modifying your system" indicator.

---

## 8. Tests

Pure layout, no permissions, no Dock writes:

- `SidebarLayout`: size, frame, row centre, flyout anchor and edge trigger for all four
  positions, including the `.top` menu-bar case and the "content taller/wider than the screen"
  clamp.
- `DockSnapshot` round-trip: unset key → restore deletes; set key → restore writes the original
  value back. This is the test that protects the user's Dock.
- Lifecycle table in §5, driven against a `FakeDockControl`: every row is one test.
- Enabling twice must not overwrite the captured snapshot.

## 9. Decisions to record

- **D51.** Dock Replacement Mode is `defaults`-based (`autohide`, `autohide-delay`,
  `autohide-time-modifier`, `orientation`) + a Dock restart. Rejected
  `NSApplicationPresentationHideDock`: presentation options apply only while the owning app is
  active, and Nexus is an `LSUIElement` that never activates — the Dock would return the instant
  focus moved.
- **D52.** Amends **D14** ("Nexus never modifies the user's Dock settings"): it may, but only on
  explicit user action, only while running, and only with a captured snapshot that distinguishes
  an unset key from a set one.
- **D53.** Hover-expand is vertical-only; horizontal orientation is icons plus flyout.

## 10. Risks

| Risk | Mitigation |
|---|---|
| Dock restart flickers the screen and closes Launchpad | Only on toggle and quit, never periodically |
| User changes Dock settings while mode is on | Snapshot is stale, restore overwrites their newer choice. Re-capture on every apply, and the status line shows live state |
| `autohide-delay` is a documented-nowhere key | It is a plain preference, ignored if Apple drops it; the mode degrades to ordinary auto-hide, not to breakage |
| macOS update resets the keys | Nothing to do; next launch re-applies |

## 11. Out of scope for M8

Drag-to-reorder (`ponytail:` note already in `SidebarView`), per-display position overrides,
Dock-style magnification, running-app indicators beyond the current dot, Spaces integration.

## What the setting became (D78)

The toggle in the sketch above shipped as a two-way choice, because it is one decision and the
toggle read as a preference. *My Dock* hides the macOS Dock while Nexus runs; *A sidebar* leaves it
alone. The stored field is unchanged (`dock.replacementEnabled`); what changed is that the pane says
which of the two you are looking at, and what it means. Running Nexus along the bottom edge with the
system Dock still there gives you two docks, which nobody chose on purpose — and until the choice
was phrased as a choice, that was the default experience.

