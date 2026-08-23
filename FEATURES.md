# Nexus — MVP Features

Every feature from Foundation §28, mapped to its milestone and required permission.
Permission column: **None** means the feature works with everything denied.

Legend — M1…M7 = milestone (see `ROADMAP.md`).

---

## MUST HAVE

| # | Feature | Milestone | Permission | Notes |
|---|---|---|---|---|
| 1 | Native macOS application | M1 | None | Agent app (`LSUIElement`), Swift + SwiftUI/AppKit |
| 2 | Vertical sidebar | M2 | None | Non-activating borderless `NSPanel` |
| 3 | Left/right positioning | M2 | None | Live-applied from configuration |
| 4 | App launcher | M2 | None | `NSWorkspace.openApplication` |
| 5 | Running application detection | M3 | None | `NSWorkspace` notifications, event-driven |
| 6 | Launch applications | M2 | None | |
| 7 | Quit applications | M3 | None | `NSRunningApplication.terminate()`; force-quit in context menu |
| 8 | Pin applications | M2 | None | Persisted as ordered bundle identifiers |
| 9 | Reorder applications | M2, M9 | None | Drag any row onto any other — pinned or running — and the rows move live under the drag; the order is stored on drop (D59, D63). Dragging across the separator pins or unpins. Context menu: Move Up / Move Down / Move to End |
| 10 | Window grouping | M4 | **Accessibility** | Flyout listing an app's windows |
| 11 | Activate windows | M4 | **Accessibility** | `AXRaise` + `NSRunningApplication.activate()` |
| 12 | Window count | M3 | None | `CGWindowListCopyWindowInfo` — count only, no titles |
| 13 | Basic window preview | M4 | **Screen Recording** *(optional)* | ScreenCaptureKit; degrades to title-only |
| 14 | Global keyboard shortcut | M5 | None | `RegisterEventHotKey`; Option+Space default |
| 15 | Search UI | M5 | None | Command-palette `NSPanel` |
| 16 | Application search | M5 | None | In-memory index of `/Applications`, `~/Applications`, system apps |
| 17 | Window search | M5 | **Accessibility** | Provider yields nothing when denied; rest of search unaffected |
| 18 | Basic file search | M5 | None | `NSMetadataQuery` over the user scope |
| 19 | Basic actions | M5 | None | See the Actions table below |
| 20 | Settings | M6 | None | General / Appearance / Behavior / Search / Permissions |
| 21 | Persistence | M1 | None | Versioned `Codable` in `UserDefaults` |
| 22 | Multi-monitor awareness | M2 (basic) → M7 (full) | None | Placement at M2; reconnect stability and per-display config at M7 |
| 23 | Dark/light mode | M2 | None | System materials, no hard-coded colors |
| 24 | Keyboard navigation | M5 (palette) → M7 (sidebar) | None | Palette is keyboard-first from day one |
| 25 | Accessibility basics | every milestone | None | Labels written with the view, not retrofitted; audited at M7 |

### Basic actions shipped in the MVP (§13)

| Action | Milestone | Permission | Implementation |
|---|---|---|---|
| Quit `<application>` | M5 | None | `NSRunningApplication.terminate()` |
| Open Terminal | M5 | None | `NSWorkspace.openApplication` |
| Open Downloads / Documents / Home | M5 | None | `NSWorkspace.open(URL)` |
| Open System Settings | M5 | None | `x-apple.systempreferences:` URL |
| Show Desktop | — | — | **Not in MVP** — no such bundle exists on macOS 14+; the alternatives need Accessibility or AppleScript (D28) |
| Lock Screen | M5 | None | `SACLockScreenImmediate` (login framework) |
| Trash | M9 | None | Always-present row before Search, drawn with the macOS Trash icons and showing full vs empty (counted with `stat`, no Full Disk Access — D58). Click opens it; the context menu opens or empties it, asking first |

No shell execution, no AppleScript, no `osascript` in the MVP. Those need Automation
permission and belong to the automation engine (§46, out of scope).

---

## SHOULD HAVE

| Feature | Milestone | Permission | Notes |
|---|---|---|---|
| Auto-hide | M2 | None | Edge-hover reveal, configurable delay |
| Hover expand | M2 | None | Widened panel with names; must not steal focus |
| Drag and drop | M2 (pin from Finder), M9 (reorder) | None | Dropping an `.app` onto the sidebar pins it. Dragging a row onto another reorders the pins, and dragging a running application onto them pins it in that slot. Dropping files onto an app icon remains out of scope |
| Smooth animations | M2 → M7 | None | Reduce Motion honoured from the first animation written |
| Custom icon size | M2 | None | |
| Custom sidebar width | M2 | None | |
| Custom opacity | M2 | None | |
| Recent applications | M6 | None | Derived from frecency data already collected for ranking |
| Window title preview | M4 | **Accessibility** | Title-only preview; the zero-cost fallback for #13 |
| Spotlight shortcut status | M6 | None | Read-only heuristic on `com.apple.symbolichotkeys` key 64. If readable, the Spotlight guide shows a live "still enabled / disabled ✓" status; if not, the guide is static (review Note 2, D33) |

---

## NICE TO HAVE

| Feature | Milestone | Permission | Decision |
|---|---|---|---|
| Advanced window thumbnails | M7 *(if budget allows)* | **Screen Recording** | Live-ish refresh on hover only; never a capture loop |
| Folder stacks | — | None | **Deferred past MVP.** Not in §33's Definition of Done |
| Multiple sidebar configurations | — | None | **Deferred.** Configuration versioning keeps the door open (§43 profiles) |
| Per-monitor configuration | M7 *(structure only)* | None | Configuration stores a display-keyed dictionary with one entry; UI ships post-MVP |

---

## Explicitly out of the MVP (§28, §101)

AI · full automation engine · plugin marketplace · widget system · workspaces and workspace
restoration · cloud sync · accounts · telemetry · remote control · Finder/Terminal/browser
replacement · window tiling and move-to-display (§88) · system control center (§38) ·
diagnostics (§39) · profiles (§43) · Sparkle auto-update (§77) · notarized public
distribution (§111.3).

The architecture must not *block* these (§20). It must not *contain* them.

---

## Permission summary

| Permission | First required | Features lost when denied | Nexus still usable? |
|---|---|---|---|
| **None (M1–M3)** | — | — | Full launcher, pinning, running apps, window counts, settings |
| **Accessibility** | M4 | Window lists, window titles, window activation, window search | Yes — everything above still works |
| **Screen Recording** | M4 *(optional)* | Window thumbnails only | Yes — title-only window lists |

Nexus never requests a permission at launch, never re-prompts after a denial, and never
blocks a feature behind a permission it does not actually need (§25, §64).
