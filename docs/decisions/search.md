# Decisions — Search

The palette, its providers, the application index, scopes and shortcuts.

Part of the decision log; the index, and the rule these follow, are in
[`../decisions.md`](../decisions.md). Numbers are global and never reused, so the gaps
here are entries that live in another file, and the date each was made is in `git log`.

## D6. `SearchResult` carries a `NexusActionDescriptor` value, not a closure.
Keeps results `Sendable`, comparable and testable without executing side effects, and gives the
§81 action model a place to grow.

## D7. Debounce is per provider (file 120 ms, everything else 0 ms), not global.
A global debounce would spend the entire 50 ms budget waiting for data already in memory.

## D8. The application index is an `NSMetadataQuery`, not a directory scan.
Spotlight already indexes every application bundle anywhere on disk and pushes live updates —
no `FSEvents` watcher, no refresh timer. Directory scan is the fallback when Spotlight is
disabled.

## D26. The search palette starts on the non-activating key path and self-measures.
Review Note 1. `SearchPanelController` opens with `makeKeyAndOrderFront` and no `NSApp.activate()`;
200 ms later it logs `strategy / isKeyWindow / NSApp.isActive / frontmost` and switches to
activate-and-restore for the rest of the session if the panel did not become key. Checking
`isKeyWindow` synchronously does not work — activation has not settled yet, and an immediate
check falls back every time. `design/mvp.md` §2.2 now documents both paths.
**Measured 2026-08-22 on an unlocked session: `strategy nonActivating, key true, app active
true, frontmost com.apple.TextEdit`. Review Note 1 is confirmed — the panel becomes key and
accepts typing while the frontmost application stays TextEdit, so there is no restore step and
no focus flicker. Path A is the shipping path.** (`NSApp.isActive` reads `true` because AppKit
counts owning the key window as active; the number that matters is
`NSWorkspace.frontmostApplication`, which never changed.) Earlier attempts read
`key false / frontmost com.apple.loginwindow` purely because the screen was locked, which makes
key-window semantics meaningless — a locked session is not a valid measurement environment.

## D27. The search field is an `NSTextField` behind `NSViewRepresentable`.
Review Note 1 predicted this: SwiftUI `TextField` focus is unreliable in a non-activated
application, and the palette must accept the first keystroke after the hotkey. `↑ ↓ ⏎ ⇧⏎ ⎋` are
handled through `control(_:textView:doCommandBy:)`; `⌘1`–`⌘9` through a local event monitor
installed only while the palette is visible.

## D28. "Show Desktop" is dropped from the MVP action list.
`FEATURES.md` names `com.apple.showdesktop`; no such bundle exists on macOS 14+ (the only match
is `WindowManagerShowDesktopEducation.app`, a tutorial). The only implementations are a
synthesised F11 key event, which needs Accessibility, or AppleScript, which D15 forbids. Dropped
for the same reason as Empty Trash. The other six actions ship.

## D29. "Lock Screen" resolves `SACLockScreenImmediate` at runtime with `dlopen`/`dlsym`.
It lives in `login.framework`, a private framework, so it cannot be linked. Resolving it at
runtime means a future macOS that removes it makes the action fail quietly and log, rather than
breaking the build or crashing. Verified present on macOS 26.6.

## D30. The application index is a one-shot Spotlight query rebuilt on application-launch events,
not a live `NSMetadataQuery`.
D8 asked for Spotlight, and this uses it — 454 applications
indexed on the development machine — but keeping a query live for the process lifetime is
background churn for a catalogue that changes when software is installed. The index is built
lazily on the first palette open (cold start stays under budget) and rebuilt when an application
launches, which is when a newly installed application first matters. Directory scan remains the
fallback when Spotlight returns nothing.

## D31. Windows for search come from a snapshot refreshed when the palette opens.
Enumerating every application's windows over AX on each keystroke would blow the 50 ms budget.
`WindowService` keeps the last enumeration, `AXObserver`s keep it fresh, and opening the palette
triggers one full refresh — a user event, not a timer. Measured: 454 applications plus 200
windows ranked in under 50 ms.

## D33. The Spotlight shortcut status is read when the guide appears, not polled.
Review Note 2, implemented as progressive enhancement: `CFPreferencesCopyAppValue` on
`com.apple.symbolichotkeys` key 64. `enabled`/`disabled` drives a live status line; anything
unexpected reads as `unknown` and the guide falls back to its static text. Read on appear rather
than on a timer, because the user leaves the screen to change the setting and comes back —
D13's single poll stays single.

## D40. The palette keeps a selection only once the user has moved it.
Root cause of "Enter executes nothing". `apply(_:)` kept any still-present `selectedID`
unconditionally, so the first provider to answer set row 0 and the merge that followed left the
selection stranded on a row that was no longer first. Live evidence: for the query `calcul`,
`results[0]` was Calculator (0.90) while `selectedID` was `window:com.barebones.bbedit#2666`.
Enter did execute — it raised a background BBEdit window, which looks exactly like nothing
happening. The rule now matches `design/mvp.md` §4.1 as written: row 0 is preselected on every
snapshot **until** the user arrows or clicks. Hover highlights without pinning, because the
palette opens under the pointer and would otherwise hand Return to whatever row the mouse
happened to be resting on.

## D68. The application index lists what a person can launch, not every bundle on the disk.
Spotlight returns 454 bundles here; the start menu made that visible by showing
`ABAssistantService`, `AddressBookManager` and `Ainu Input Method` in a grid. Bundles declaring
`LSUIElement` or `LSBackgroundOnly`, helpers nested inside another `.app`, input methods and the
`CoreServices` scaffolding are filtered out — 132 remain. The palette gets the same filter, since
nobody was searching for those either.

## D69. The start menu's height is computed, not measured.
A `LazyVGrid` inside a `ScrollView` reports no intrinsic height, so `fittingSize` measured the
field and the action row alone and the panel opened as a 106 pt sliver. The height comes from the
row count instead. The panel also has to be told when the index finishes building, since it opens
before the first build completes — `ApplicationIndex.onIndexed`.

## D87. Scopes are `⌃1`…`⌃6`, not `⌘1`…`⌘6`.
`design/search-scope.md` asked for `⌘1`…`⌘6`. Those keys were already taken, and visibly so: every
result row in the palette draws its own `⌘N` badge and running the numbered result is how the
keyboard-first path works. A chord that means "run result 3" in one build and "search folders only"
in the next is worse than a chord nobody guesses first time.

So the digits move one modifier over: `⌘N` runs a result, `⌃N` picks a scope, and `⇥` / `⇧⇥` cycle
through the six for the hand that is already on the keyboard. `⇥` is handled in the field editor's
`doCommandBy` rather than a key monitor, because the palette has exactly one control and Tab would
otherwise walk focus out of it.

The chip that shows the current scope is also the menu that changes it, so the whole feature is
reachable with the mouse — and picking from that menu hands first responder back to the field
without selecting what is in it, or the next keystroke would replace the query the scope was chosen
for.

## D90. The shortcut centres the palette; the bar's box opens it beside itself.
M19 shipped `search.opensAtBar`, defaulting to on, which made `⌥Space` open the palette against the
bar. That was wrong about what a global shortcut means: pressing a hotkey is not pointing at the
bar, and Spotlight — the thing every macOS user compares this to — answers in the middle of the
screen. The shortcut now always centres the palette, and nothing can configure that away.

What the bar can do instead is *look* like a search field. `search.barStyle` chooses between an
icon in one slot, which opens the centred palette, and a box across three slots, which opens the
palette beside itself. The box is drawn with the same one-view-across-N-slots trick as the wide
player (D82), so the layout maths stays row-based, and it collapses back to an icon on a narrow
vertical bar for the same reason the player does.

The box is a box, not a field. This panel can never become key, so an `NSTextField` drawn in it
could not be typed into — the constraint from `design/mvp.md` §2.1 that also killed the original
"type in the dock" request. Clicking the box opens the palette 8 points away, which is where every
keystroke goes; the effect a user sees is a field that grows into a result list.

`opensAtBar` is gone rather than migrated: it was one commit old, and the placement is now decided
by *which surface asked* rather than by a setting.

## D98. System Settings panes are read from the extension directory, not asked of Spotlight.

The Settings scope shipped in M19 pointing at the action provider, which knew about Nexus's own
actions and nothing about System Settings. Finishing it needed a list of panes, and the obvious
source does not work: System Settings has been a set of ExtensionKit extensions since macOS 13, and
the panes on the sealed system volume are not Spotlight-indexed —
`kMDItemContentType == 'com.apple.systempreference.prefpane'` returns **nothing** on this machine.

`/System/Library/ExtensionKit/Extensions` is the list. Each `.appex` carries
`EXAppExtensionAttributes.SettingsExtensionAttributes`, which names the legacy identifier that
`x-apple.systempreferences:` opens and says whether the extension accepts that scheme at all — the
ones that do not are skipped, since a search result that does nothing is worse than no result. Read
once and cached: the set changes when macOS is updated, and the process does not outlive an update
(§65).

Names take one rule, because the extensions' own are uneven: `Displays` and `Screen Time` are right,
`AccessibilitySettingsExtension` and `MouseExtension` are not. Where the extension names a legacy
`.prefPane`, that pane's `CFBundleName` wins — it is the string System Preferences drew — and
otherwise the bundle name is tidied: a trailing `Extension` dropped, `DateAndTime` split back into
words.

The scope is now called **Settings & Actions**. It reaches one provider holding both, and a filter
whose name promises one of the two things it returns is a small lie told six times a day.
