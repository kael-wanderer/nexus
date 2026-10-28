# Nexus app review and improvement plan

Date: 2026-10-27 · Reviewed commit: 45b5c1b · Status: proposal, not an implementation commitment.

## Recommendation

Make the next release about confidence and daily usability: safe settings persistence, a passing test baseline, reliable focus and window interactions, relevant search, and settings that take people directly to the control they need. Nexus already has enough features to deliver its core promise. Preserve the native, local, permission-aware dock and launcher design.

## Evidence and limits

Reviewed the repository README, roadmap, verification log, architectural documentation, selected source through CodeGraph, all four Nexus BugMind maps, saved screenshots, and the running bar's accessibility tree and screenshot. The live bar exposes named buttons, running states, window counts, groups, volume and the clock. Its visible middle sections show only a subset of the applications available in the accessibility tree; scrolling is already supported, so this is a discoverability opportunity rather than proof of missing applications.

Ran `swift test` on Apple Swift 6.4. All 209 NexusCore tests passed. NexusUITests terminated with signal 5 and `Fatal error: Index out of range`. A second run, `swift test --filter NexusUITests`, reproduced the crash. The failing test/root cause has not been isolated; this does not establish that the running application crashes. Compilation also warned about redundant `#require` in Tests/NexusUITests/ClockAndVolumeTests.swift:105. Historical “516 tests, zero warnings” is not a current verified baseline.

The native UI inspection was limited. An attempted default search shortcut did not expose a palette through automation; configuration, focus or synthetic-input handling may explain that. Do not classify it as a confirmed shortcut defect. Search and settings visual observations below use the checked-in screenshots, with source confirmation where stated. No full VoiceOver, physical monitor reconnect, audio-device or clean-machine release pass was performed. App behavior was not changed as part of this review.

## Findings

### R1 — High: newer-version configuration can be overwritten

Source-confirmed write path: ConfigurationStore.loadThrowing (Sources/NexusCore/Configuration/ConfigurationStore.swift:83) returns defaults when it encounters a newer schema and promises to leave the bytes untouched. However, Composition.start (Sources/NexusApp/Composition.swift:128) immediately calls configuration.flush(). ConfigurationController.flush/write (Sources/NexusCore/Configuration/ConfigurationController.swift:38,53) calls save, and ConfigurationStore.save (:119) unconditionally writes the current version. Thus the startup path defeats downgrade protection even without a user editing settings.

Plan: represent load compatibility as an explicit writable/read-only state; enforce it at the storage write boundary so startup, debounce, shutdown and future callers cannot bypass it. Preserve the original bytes. Offer an explicit backed-up reset only when the user chooses it. Test a future-schema payload through load → controller flush → edit → flush and assert the stored bytes remain identical. Include successful older-schema migrations and normal current-version saves. Estimate: 1–2 engineering days including tests.

### R2 — High: the current UI test baseline crashes

Observed twice on this toolchain. Do not ship against a historical pass count. Isolate the failing suite/test, capture a symbolicated stack, and determine whether this is a product bounds error, timing assumption in a test, shared state, or toolchain compatibility issue. Repair the cause instead of broadly disabling tests or only increasing delays. Remove the redundant test assertion warning. Establish a macOS CI job for build, unit tests and warning checks; the checkout currently contains no .github workflow directory. Validate on the minimum supported macOS and a current supported system, using a documented Xcode version.

Acceptance: full suite exits zero, no unexpected warnings, isolated regression test covers the cause, and a repeat run confirms timing-sensitive repairs. Record toolchain, OS and actual count. Estimate: 2–4 days, provisional until isolated.

### R3 — Medium: settings search has a wrong destination and stops too early

SettingsSearch.entries (Sources/NexusUI/Settings/SettingsSearch.swift:95) indexes Position under Appearance. DockPane actually renders SidebarPositionPicker (Sources/NexusUI/Settings/SettingsView.swift:224). The jump handler (:105) only selects a tab and clears the query; it cannot scroll to or identify the specific control. SettingsEntry.id is derived from tab plus localized title, which is unsuitable as a durable control identifier. Existing comments say tests ensure tab representation, not complete routing coverage.

Plan: immediately correct Position's destination. Give searchable controls stable identifiers and destinations. Extend navigation to select category, scroll to the row, briefly highlight it and provide accessible focus/announcement. Share metadata between controls and search where practical, without turning every settings view into a generic form framework. Test every indexed destination, repeated labels, empty results and keyboard selection. Estimate: 2–3 days for routing and control navigation.

### R4 — Medium: file results are technically matching but often unhelpful

The saved search screenshot for “safari” shows multiple Chrome Application Support folders occupying the file results. FileSearchProvider (Sources/NexusCore/Search/Providers.swift:95) searches the home directory using a display-name prefix, then ranks candidates; it does not provide user-facing root selection here. Fuzzy ranking cannot recover relevant candidates excluded by prefix-only retrieval.

Plan: establish a representative query corpus first. Add configurable included locations and default filtering of implementation/cache directories, with an explicit way to include them. Preserve useful developer folders rather than excluding all code. Apply filtering before candidate limits where possible so excluded matches do not consume the budget. Improve filename token matching with bounded retrieval; use location and recency only as understandable ranking signals. Show concise parent-folder context, with full path available on demand. Preserve stable keyboard selection as slower file results merge. Estimate: 3–5 days.

Acceptance: on the agreed corpus, exact app names rank first; irrelevant browser cache folders do not fill normal file results; intended documents appear in the top five for at least 90% of corpus queries; opted-in excluded folders remain findable. Preserve the existing application/window engine budget below 50 ms on recorded reference hardware. Measure keystroke-to-visible-result separately, and report file-provider latency separately from in-memory search.

### R5 — Medium: interaction quality needs a release gate

The verification log still has outstanding window-switcher, hover-panel, settings typing, calendar, audio-device and hardware checks. BugMind lists NX-0044 through NX-0046 as open/unconfirmed, not established product defects. The earlier live checks found real issues that unit tests had missed: Finder drops intercepted by overlays, minimized-window enumeration and keyboard focus behavior.

Plan: turn these into a small repeatable release walkthrough with exact steps, expected outcomes, build identity and evidence. Prioritize search/window switcher open → type → select → Escape → continue typing in the previous app; drag between pinned/running/groups and from Finder; cancel a drag; switch displays; revoke permissions; full-screen behavior; window disappearance during selection; quit confirmation and New Window. Exercise headphone/default-output changes and HDMI with no settable volume, plus monitor unplug/replug and sleep/wake. Do not close open issues merely because synthetic input fails.

Acceptance: all core journeys pass on the installed candidate, denied permissions leave supported functions usable, focus returns correctly, and physical-device checks have explicit pass/fail evidence. Estimate: 2–3 days of setup/execution, fixes additional depending on findings.

### R6 — Medium: settings and bar density can be clearer

The settings screenshot has nine horizontal tabs and long explanatory blocks. SettingsView also imposes a fixed 620 × 790 content frame (:45) despite comments about resizing. This should be tested on smaller available screen heights and larger text, not assumed to adapt because the outer window is resizable.

Plan: move categories to a macOS-style sidebar, keep search consistently reachable, use flexible content sizing with scrolling and a sensible minimum, and group controls by the user's task. Shorten default help text and disclose advanced explanations. Keep the current meaningful separation between placement, contents and appearance, with clearer names where needed. Show a compact layout preview while adjusting icon size/spacing. On the bar, make scroll overflow discoverable and give reorder/group/unpin distinct feedback. Existing insertion indicators and edit mode should be refined, not rebuilt from scratch. Add undo for pin/unpin/group edits if a small command history can cover them reliably.

Acceptance: settings fit a 1280 × 800 display with accessible navigation to every row; search reaches the exact control; bar overflow is discoverable; group creation and cancellation succeed without accidental unpinning. Evaluate changes with 3–5 target users using concrete tasks. Estimate: 4–6 days, after R3 and the interaction baseline.

### R7 — Medium: complex interaction code needs more local ownership

SidebarViewModel is 1,569 lines, PanelController 1,067 and Composition 556. Size alone is not a defect, but the historical bugs concentrate around drag intent, overlays, focus, display anchoring and panel lifetime. Refactor these behaviors as needed while fixing them.

Plan: extract a drag-session module handling intent, hover target, reorder/group/unpin, commit and cancel; keep rendering driven by its state. Separate display placement from panel visibility/focus transitions in PanelController. Keep Composition focused on wiring. Inject platform work behind existing test seams; do not add protocols solely to make every class symmetrical. Test sequences through the resulting interface: target disappears mid-drag, group reaches capacity, display disconnects with a flyout open, permission is revoked while previews load, and focus is handed back after cancellation.

Acceptance: callers no longer coordinate those internal state transitions, behavior tests cover interruptions, and no behavior or performance regression. Estimate: 3–5 days, interleaved with fixes rather than a rewrite prerequisite.

### R8 — Conditional release work: distribution and truthful project status

README's top status says M1–M23 while its roadmap and BugMind say M1–M27. BugMind's recorded repository head is also older than the reviewed checkout. README's claim that the app never changes a system setting is too broad for its opt-in Dock replacement feature. Its “exactly one poll” assertion also needs checking against media position behavior. Reconcile claims instead of repeating them as current measurements.

Plan: update the release checklist, version/status copy, supported toolchain, known limitations, screenshots and actual verification evidence. Preserve a distinction between implemented, tested and released. For wider distribution, acquire/configure Developer ID, sign the release build, submit with notarytool, staple and verify the deliverable, then test a quarantined download on a clean Mac. Set up a hosted version manifest before implementing update checking. Begin with explicit check → release notes → download; automatic installation is outside the current scope.

Acceptance: consistent version/build identity across app, package and release notes; verified distribution artifact; clear offline/failure states for update checks; installation and login-item path verified. Estimate: 2–4 days engineering after credentials and hosting exist, excluding external enrollment/review delays.

Apple references checked 2026-10-27: [Settings guidance](https://developer.apple.com/design/human-interface-guidelines/settings), [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Customizing notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Proposed delivery sequence

Estimates assume one experienced macOS engineer. These are effort ranges, not promised dates; hardware checks and release prerequisites can extend elapsed time.

| Stage | Work | Exit gate | Effort |
|---|---|---|---|
| A: trustworthy baseline | R1, R2, immediate R3 route fix; record current evidence | Future settings preserved; full suite green; Position reaches Dock | 3–6 days |
| B: reliable daily journeys | R5 plus targeted R7 changes | Focus, drag, windows, permissions and display walkthrough passes | 5–8 days |
| C: easier discovery | R3 exact-control navigation, R4 search relevance, R6 settings/bar improvements | Query corpus and task-based usability checks pass | 8–12 days |
| D: release candidate | R8, final regression pass and packaging | Installed candidate and distributable both verified | 2–4 days plus external waits |

Allow roughly 4–6 engineering weeks for this scope, with contingency if crash isolation or platform integration reveals larger problems. Stage A should start first; do not make the settings redesign a dependency of the data-preservation fix. Credentials/hosting can be prepared while other work proceeds.

## Suggested ownership and task breakdown

No individuals are assigned. macOS/core owner: R1 and storage regression, R2 root cause with test owner, search candidate policy, platform behavior fixes. UI owner: R3 destinations, R6 responsive settings, drag feedback and accessibility. QA/release owner: query corpus, installed-build journey matrix, CI and packaging evidence. Product owner: default search exclusions, terminology and usability task selection. One person may fill all roles.

The first five tasks should be: (1) isolate UI-test crash, (2) close configuration write hole with a regression, (3) fix Position route and add routing coverage, (4) establish the installed-build smoke checklist, (5) define the file-search corpus and exclusion defaults. Each task should link evidence and acceptance criteria above before implementation begins.

## What to defer

Respect the existing product decisions. Do not add AI, cloud accounts/sync, automation, plugins, widgets, a full diagnostics center, workspaces, profiles or window tiling to this plan. Per-display edge/width and full-screen edge reveal were explicitly dropped; reopening them is a separate product decision. Avoid building a second group model for running apps until the existing open decision is settled. Improve the existing Copy Version Details flow and documentation before considering a diagnostics subsystem.

## Success measures

Zero failures in the complete test run on the declared supported toolchain; byte-for-byte preservation of newer configuration; all settings destinations valid; all release-critical manual checks recorded; relevance targets met on a published local test corpus; no unintended focus theft; no unbounded memory growth in a 30-minute recorded soak. Re-measure cold start, idle CPU and memory on a named machine rather than treating historical measurements as today's results. Keep evaluation local: no telemetry is needed for this plan.
