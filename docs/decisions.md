# Decisions

Ambiguity calls made during implementation, per the §32 rule: pick the simplest native macOS
option that preserves extensibility, record it, continue.

Format: **decision — reason — alternative rejected.**

One entry per call, numbered in the order they were made and never renumbered. Ninety-odd of them in
one file stopped being a log and started being a haystack, so the entries live in six files by area.
The numbers stay global — which is why each file has gaps — and this page is the index.

| | |
|---|---|
| [`decisions/foundation.md`](decisions/foundation.md) | Build, configuration, the event bus, logging, measurement — the decisions everything else stands on. |
| [`decisions/bar.md`](decisions/bar.md) | Panels and focus, zones and rows, dragging, and what a dock slot can be: an application, a group, a folder. |
| [`decisions/windows.md`](decisions/windows.md) | The Accessibility window layer: counts, titles, flyouts, thumbnails, reserved space, minimized windows. |
| [`decisions/search.md`](decisions/search.md) | The palette, its providers, the application index, scopes and shortcuts. |
| [`decisions/media.md`](decisions/media.md) | What is playing, who is playing it, and whether it is playing at all. |
| [`decisions/system.md`](decisions/system.md) | Permissions, displays, and the macOS Dock Nexus replaces. |

## Every decision

| | | |
|---|---|---|
| **D1** | Build system: SwiftPM package + `Makefile`, no checked-in `.xcodeproj` | [Foundation](decisions/foundation.md) |
| **D2** | Bundle identifier `com.congbui.nexus`, fixed permanently | [Foundation](decisions/foundation.md) |
| **D3** | Sidebar panel can never become key; the search palette activates the app deliberately | [The bar](decisions/bar.md) |
| **D4** | Auto-hide reveal uses a 2 pt transparent edge-trigger panel with a tracking area | [The bar](decisions/bar.md) |
| **D5** | Window counts come from `CGWindowListCopyWindowInfo`, titles from the AX API | [Windows](decisions/windows.md) |
| **D6** | `SearchResult` carries a `NexusActionDescriptor` value, not a closure | [Search](decisions/search.md) |
| **D7** | Debounce is per provider (file 120 ms, everything else 0 ms), not global | [Search](decisions/search.md) |
| **D8** | The application index is an `NSMetadataQuery`, not a directory scan | [Search](decisions/search.md) |
| **D9** | Configuration lives in `UserDefaults` as versioned JSON; migrations operate on the JSON
dictionary | [Foundation](decisions/foundation.md) |
| **D10** | A newer-versioned configuration is left on disk untouched and defaults are used in
memory | [Foundation](decisions/foundation.md) |
| **D11** | Displays are identified by `CGDisplayCreateUUIDFromDisplayID`, not `CGDirectDisplayID` | [The system around Nexus](decisions/system.md) |
| **D12** | `EventBus` is a ~40-line typed multicast over `AsyncStream` | [Foundation](decisions/foundation.md) |
| **D13** | Exactly one poll exists in the app: permission status at 1 Hz while a permission screen
is visible | [The system around Nexus](decisions/system.md) |
| **D14** | Nexus never modifies the user's Dock settings | [The system around Nexus](decisions/system.md) |
| **D15** | No shell execution, AppleScript or `osascript` in the MVP | [Foundation](decisions/foundation.md) |
| **D16** | Configuration stays at version 1; no v1→v2 migration was manufactured | [Foundation](decisions/foundation.md) |
| **D17** | `Force Quit` is always present in the sidebar context menu, not revealed "after a
timeout" | [The bar](decisions/bar.md) |
| **D18** | Window counts are recomputed on every `NSWorkspace` application event and whenever the
pointer enters the sidebar | [Windows](decisions/windows.md) |
| **D19** | The running-but-unpinned section shipped with the sidebar at Milestone 2 | [The bar](decisions/bar.md) |
| **D20** | `#expect` comparisons keep both sides in `CGFloat` | [Foundation](decisions/foundation.md) |
| **D21** | The window flyout opens on click or from the context menu, not on hover dwell | [Windows](decisions/windows.md) |
| **D22** | `AXObserver` callbacks publish one coalesced `.windowsChanged(app)` per application
instead of per-window created/closed/retitled/focused events | [Windows](decisions/windows.md) |
| **D23** | `EventBus` subscriptions are created synchronously inside `start()`, not inside the
consuming `Task` | [Foundation](decisions/foundation.md) |
| **D24** | The flyout's whole content is gated on `target != nil` | [Windows](decisions/windows.md) |
| **D25** | Only `AXStandardWindow` subroles appear in window lists | [Windows](decisions/windows.md) |
| **D26** | The search palette starts on the non-activating key path and self-measures | [Search](decisions/search.md) |
| **D27** | The search field is an `NSTextField` behind `NSViewRepresentable` | [Search](decisions/search.md) |
| **D28** | "Show Desktop" is dropped from the MVP action list | [Search](decisions/search.md) |
| **D29** | "Lock Screen" resolves `SACLockScreenImmediate` at runtime with `dlopen`/`dlsym` | [Search](decisions/search.md) |
| **D30** | The application index is a one-shot Spotlight query rebuilt on application-launch events,
not a live `NSMetadataQuery` | [Search](decisions/search.md) |
| **D31** | Windows for search come from a snapshot refreshed when the palette opens | [Search](decisions/search.md) |
| **D32** | Settings and onboarding are ordinary titled `NSWindow`s, and Nexus activates itself to
show them | [The system around Nexus](decisions/system.md) |
| **D33** | The Spotlight shortcut status is read when the guide appears, not polled | [Search](decisions/search.md) |
| **D34** | Settings write through `ConfigurationController.binding(_:)` | [Foundation](decisions/foundation.md) |
| **D35** | Measured performance, recorded rather than estimated (§68: measure before optimising) | [Foundation](decisions/foundation.md) |
| **D36** | The sidebar gets VoiceOver navigation, not arrow-key navigation | [Windows](decisions/windows.md) |
| **D37** | Accessibility revocation is detected on the next AX call, not by polling | [Windows](decisions/windows.md) |
| **D38** | The 30-minute Instruments session in the Milestone 7 acceptance criteria was run as a
150-second scripted churn instead | [Foundation](decisions/foundation.md) |
| **D39** | Clicks inside a panel that can never become key are handled in AppKit, not by SwiftUI's
`.onTapGesture` | [The bar](decisions/bar.md) |
| **D40** | The palette keeps a selection only once the user has moved it | [Search](decisions/search.md) |
| **D41** | `make` signs with any stable codesigning identity, not only "Apple Development" | [Foundation](decisions/foundation.md) |
| **D42** | The grant screen offers a restart once the user has been to System Settings | [The system around Nexus](decisions/system.md) |
| **D43** | Action outcomes, permission transitions and lifecycle events log at `.notice` | [Foundation](decisions/foundation.md) |
| **D44** | Pinned reorder is available from the context menu | [The bar](decisions/bar.md) |
| **D45** | "The sidebar only shows Calculator" was contaminated test state, not a defect | [Foundation](decisions/foundation.md) |
| **D46** | The sidebar scrolls | [The bar](decisions/bar.md) |
| **D47** | "Persisted logging still produces nothing" is a shell collision, not a logging fault | [Foundation](decisions/foundation.md) |
| **D48** | Every remaining `.info` call was raised to `.notice` | [Foundation](decisions/foundation.md) |
| **D49** | The frontmost application is seeded at monitor start | [The system around Nexus](decisions/system.md) |
| **D50** | `.main` resolves to the menu-bar display, not `NSScreen.main` | [The system around Nexus](decisions/system.md) |
| **D51** | Dock Replacement Mode is `defaults` keys plus a Dock restart | [The system around Nexus](decisions/system.md) |
| **D52** | Amends D14 ("Nexus never modifies the user's Dock settings") | [The system around Nexus](decisions/system.md) |
| **D53** | Hover-expand is vertical-only | [The bar](decisions/bar.md) |
| **D54** | The Dock is parked on the edge Nexus is not using | [The system around Nexus](decisions/system.md) |
| **D55** | The Trash row has no full/empty state | [The bar](decisions/bar.md) |
| **D56** | Drag-to-reorder is an AppKit dragging session inside `PanelRowInteraction`, not SwiftUI | [The bar](decisions/bar.md) |
| **D57** | Empty Trash goes through Finder and asks first | [The bar](decisions/bar.md) |
| **D58** | Supersedes D55: the Trash row shows full vs empty again, counted with `stat` | [The bar](decisions/bar.md) |
| **D59** | A drag shows a preview order; the configuration is written once, on drop | [The bar](decisions/bar.md) |
| **D59 (extended)** | Running applications get the drag preview too | [The bar](decisions/bar.md) |
| **D60** | The window list lives in the context menu; the flyout becomes "Show All Windows" | [Windows](decisions/windows.md) |
| **D61** | Window-count badges come from the Accessibility list, and are hidden without it | [Windows](decisions/windows.md) |
| **D62** | A window with no AX subrole is not a window | [Windows](decisions/windows.md) |
| **D63** | The running section has a user order too, and a drag can cross the separator | [The bar](decisions/bar.md) |
| **D64** | Hover opens the flyout after a delay; switching rows while one is open is instant | [Windows](decisions/windows.md) |
| **D65** | A thumbnail arriving has to re-measure the flyout | [Windows](decisions/windows.md) |
| **D66** | The preview service's failure paths log at `.notice`, not `.debug` | [Windows](decisions/windows.md) |
| **D67** | Every configuration section decodes tolerantly, not just the root | [Foundation](decisions/foundation.md) |
| **D68** | The application index lists what a person can launch, not every bundle on the disk | [Search](decisions/search.md) |
| **D69** | The start menu's height is computed, not measured | [Search](decisions/search.md) |
| **D70** | Screen space is not reserved, windows are moved out of it | [Windows](decisions/windows.md) |
| **D71** | Grouping is asked for by resting on a row, not by dropping on it | [The bar](decisions/bar.md) |
| **D72** | The dock repairs itself rather than trusting what it stored | [The bar](decisions/bar.md) |
| **D73** | The bar has three zones, and only the middle one scrolls | [The bar](decisions/bar.md) |
| **D74** | The bar's length is measured, not configured | [The bar](decisions/bar.md) |
| **D75** | What is playing comes from public sources, or not at all | [Now playing](decisions/media.md) |
| **D76** | A player that publishes nothing is named by its window | [Now playing](decisions/media.md) |
| **D77** | The bar is six parts, and it says so | [The bar](decisions/bar.md) |
| **D78** | "Nexus is my Dock" is one choice, not a toggle in a list | [The bar](decisions/bar.md) |
| **D79** | Icons default to the size of a Dock tile | [The bar](decisions/bar.md) |
| **D80** | Position is asked for, per player, and only while somebody is looking | [Now playing](decisions/media.md) |
| **D81** | A click outside closes a popover, without waiting for the pointer to leave | [The bar](decisions/bar.md) |
| **D82** | The wide media player spans four rows rather than becoming a section of its own | [The bar](decisions/bar.md) |
| **D83** | The player asks the player, and a paused player keeps its row | [Now playing](decisions/media.md) |
| **D84** | The wide player's title goes above the scrubber, not instead of it | [Now playing](decisions/media.md) |
| **D85** | The media player has no popover | [Now playing](decisions/media.md) |
| **D86** | Nexus installs into /Applications, and says so when it has not | [Foundation](decisions/foundation.md) |
| **D87** | Scopes are `⌃1`…`⌃6`, not `⌘1`…`⌘6` | [Search](decisions/search.md) |
| **D88** | Every row carries its own accessibility action | [Windows](decisions/windows.md) |
| **D89** | The sound belongs to the application, not to the process making it | [Now playing](decisions/media.md) |
| **D90** | The shortcut centres the palette; the bar's box opens it beside itself | [Search](decisions/search.md) |
| **D91** | A bar per display, or a bar that follows the pointer — the user picks | [The system around Nexus](decisions/system.md) |
| **D92** | A browser's play state comes from its window title, because its audio never stops | [Now playing](decisions/media.md) |
| **D93** | Closing a window must not hide the application | [The bar](decisions/bar.md) |
| **D94** | A menu item that toggles says which way it toggles | [The bar](decisions/bar.md) |
| **D95** | A player that has quit is not paused | [Now playing](decisions/media.md) |
| **D96** | A folder in the dock is a path, and what it cannot read it says out loud | [The bar](decisions/bar.md) |
| **D97** | Three minimized windows, in the tail, in an order Nexus keeps itself | [Windows](decisions/windows.md) |
