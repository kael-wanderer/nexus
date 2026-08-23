# Nexus — Architecture

Decisions and their reasons. Details of the MVP surface live in `docs/design/mvp.md`;
one-off ambiguity calls live in `docs/decisions.md`.

---

## 1. Build shape

**SwiftPM package + `Makefile` that assembles and signs `Nexus.app`.** No `.xcodeproj`
checked in.

Reason: `swift build` / `swift test` run headlessly, which is what an agent-driven,
milestone-gated workflow needs. A `.pbxproj` is a merge-hostile binary-ish blob that neither
humans nor tooling edit well. §111.4 leaves the project format open.

Cost, accepted: no SwiftUI previews, no XCUITest (needs an Xcode target). §67 wants XCUITest
only for critical flows — add an Xcode wrapper project at Milestone 7 if those tests earn it.

```
Package.swift
├── NexusCore        (library)  models, services, search, config, logging, event bus
├── NexusUI          (library)  SwiftUI views + panel hosting (AppKit)
├── NexusApp         (executable) NSApplicationDelegate, wiring, composition root
├── NexusCoreTests
└── NexusUITests     (logic only; no XCUITest)
```

`NexusApp` is the only place that constructs concrete services — everything else takes
protocols by injection. The library targets never `import NexusApp`.

**Bundle identity:** `com.congbui.nexus`, fixed forever. Signed with the free Apple ID
"Apple Development" certificate (Personal Team). Never ad-hoc: macOS TCC keys Accessibility
and Screen Recording grants to the code signature, and an ad-hoc signature changes every
build, resetting every grant (§111.3).

**Deployment target:** macOS 14.0. Swift 6 language mode, strict concurrency on.

---

## 2. Module map (§19)

```
NexusApp/
  AppDelegate            NSApplicationDelegate, .accessory activation policy
  Composition            builds services, injects them, owns lifetime
  StatusItem             menu-bar item (quit, settings, toggle sidebar)

NexusCore/
  Models/                Application, Window, Display, SearchResult, NexusAction, events
  Configuration/         NexusConfiguration v1, ConfigurationStore, migrations
  Events/                EventBus, NexusEvent
  Logging/               Log.swift — os.Logger per §66 category
  Applications/          ApplicationService (actor), ApplicationMonitor
  Windows/               WindowService (actor), WindowMonitor (AXObserver), WindowPreviewService
  Search/                SearchEngine (actor), SearchProvider, {Application,Window,File,Action}Provider,
                         Ranking, Frecency
  System/                DisplayService, HotKeyService, PermissionService, LoginItemService
  Utilities/             AXValue bridging, image cache, debounce, string matching

NexusUI/
  Panels/                SidebarPanel, SearchPanel, PanelController
  Sidebar/               SidebarView, SidebarViewModel, item views, window flyout
  Search/                SearchPaletteView, SearchViewModel, result rows
  Settings/              SettingsWindow, per-pane views, ShortcutRecorder
  Onboarding/            OnboardingWindow, step views
  Permissions/           PermissionRequestView (explain-and-grant, reused by onboarding)
  Design/                colors, metrics, motion (Reduce Motion aware)
```

Rule (§62): views own no system logic. View → ViewModel (`@MainActor @Observable`) →
service protocol → macOS API. A SwiftUI file that imports `ApplicationServices` or
`ScreenCaptureKit` is a bug.

---

## 3. Service protocols

Protocols exist where they buy testability or a real second implementation. Not everywhere
(§62: "do not create protocols for every trivial type").

```swift
protocol ApplicationServing: Sendable {
    func runningApplications() async -> [NexusApplication]
    func launch(_ app: ApplicationIdentity) async throws
    func activate(_ app: ApplicationIdentity) async throws
    func quit(_ app: ApplicationIdentity, force: Bool) async throws
}

protocol WindowServing: Sendable {
    func windows(for app: ApplicationIdentity) async throws -> [NexusWindow]
    func allWindows() async throws -> [NexusWindow]
    func activate(_ window: WindowIdentity) async throws
}

protocol WindowPreviewing: Sendable {
    func preview(for window: WindowIdentity, maxDimension: CGFloat) async -> CGImage?
}

protocol SearchProvider: Sendable {
    var identifier: SearchProviderID { get }
    var weight: Double { get }                       // provider bias in ranking
    var requiredPermission: Permission? { get }      // nil = works with zero permissions
    func results(for query: SearchQuery) async -> [SearchResult]
}

protocol ConfigurationStoring: Sendable {
    func load() -> NexusConfiguration
    func save(_ configuration: NexusConfiguration) throws
}

protocol PermissionChecking: Sendable {
    func status(of permission: Permission) -> PermissionStatus
    func requestOrOpenSettings(_ permission: Permission)
    func statusStream(for permission: Permission) -> AsyncStream<PermissionStatus>
}
```

No protocol for: `HotKeyService`, `DisplayService`, `LoginItemService`, `EventBus` — one
implementation each, and their macOS calls are trivially faked in tests by injecting a closure
where a test actually needs it.

---

## 4. Concurrency (§111.4.7)

- **Services are actors.** `ApplicationService`, `WindowService`, `SearchEngine`,
  `WindowPreviewService`. AX calls in particular must never run on the main thread — a
  hung app would freeze the sidebar.
- **UI state is `@MainActor`.** ViewModels are `@MainActor @Observable` classes; views bind to
  them directly. No `ObservableObject`/Combine.
- **Models are `Sendable` value types.** `NexusApplication`, `NexusWindow`, `SearchResult`
  are structs; `CGImage` crosses boundaries only inside `@unchecked Sendable` wrappers created
  at one audited spot in `WindowPreviewService`.
- **Swift 6 language mode, strict concurrency.** Warnings are errors in CI.
- `@MainActor` exceptions: `HotKeyService` (Carbon event handlers dispatch to the main
  runloop), `PanelController` (all `NSWindow` work), `StatusItem`.

---

## 5. Events, not polling (§62, §18)

`EventBus` is a small typed multicast over `AsyncStream` — roughly 40 lines, no dependency.
`NotificationCenter` is untyped and awkward under strict concurrency; per-service streams
alone would force every consumer to know every producer.

```swift
enum NexusEvent: Sendable {
    case applicationLaunched(ApplicationIdentity)
    case applicationTerminated(ApplicationIdentity)
    case applicationActivated(ApplicationIdentity)
    case applicationsChanged
    case windowsChanged(ApplicationIdentity)   // coalesced; consumers re-read (D22)
    case displaysChanged
    case configurationChanged(NexusConfiguration)
    case permissionChanged(Permission, PermissionStatus)
}
```

Sources — all push, zero timers:

| Event | Source |
|---|---|
| application launched / terminated / activated | `NSWorkspace.shared.notificationCenter` |
| windows changed (coalesced) | `AXObserver` per running application (D22) |
| displays changed | `NSApplication.didChangeScreenParametersNotification` |
| configuration changed | `ConfigurationStore` on save |
| permission changed | polled **only** while a permission screen is on-screen, then stopped |

The last row is the single sanctioned poll: macOS has no TCC-grant notification, and §111.6
requires a live checkmark. 1 Hz, scoped to a visible screen, cancelled on dismiss.

Subscribers get their own `AsyncStream` with `.bufferingNewest(64)`; a slow consumer drops
events rather than back-pressuring producers. Consumers re-read authoritative state from the
service on wake, so a dropped event costs a refresh, never correctness.

---

## 6. Data models

Identity is the hard part — AX elements and `NSRunningApplication` are not stable across
relaunch, so nothing is persisted by object reference.

```swift
struct ApplicationIdentity: Hashable, Sendable {   // persisted form: bundleIdentifier
    let bundleIdentifier: String
    let processIdentifier: pid_t?                  // nil when not running
}

struct NexusApplication: Identifiable, Sendable {
    let identity: ApplicationIdentity
    let name: String
    let bundleURL: URL
    var isRunning: Bool
    var isActive: Bool
    var windowCount: Int
}

struct WindowIdentity: Hashable, Sendable {
    let owner: ApplicationIdentity
    let number: CGWindowID                          // stable for the window's lifetime
}

struct NexusWindow: Identifiable, Sendable {
    let identity: WindowIdentity
    var title: String
    var isMinimized: Bool
    var frame: CGRect
    var displayID: DisplayIdentity?
}

struct DisplayIdentity: Hashable, Sendable {        // persisted form: uuid
    let uuid: String                                // CGDisplayCreateUUIDFromDisplayID
}

struct SearchResult: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: ResultIcon                            // .application(bundleURL) | .file(URL) | .symbol(String)
    let category: SearchCategory
    var score: Double
    let action: NexusActionDescriptor                // value, not a closure — Sendable + testable
}
```

`NexusActionDescriptor` is an enum (`launchApplication`, `activateWindow`, `openFile`,
`openURL`, `quitApplication`, `runBuiltInAction`) resolved by an `ActionRunner` in the app
layer. Making results carry data rather than closures keeps them `Sendable`, comparable, and
unit-testable without executing anything, and gives §81's action model somewhere to grow.

---

## 7. Persistence (§16, §74, §111.4.4)

One versioned `Codable` struct, JSON-encoded into `UserDefaults` under `configuration`.

```swift
struct NexusConfiguration: Codable, Sendable, Equatable {
    static let currentVersion = 1
    var version: Int = currentVersion
    var general: GeneralConfiguration
    var appearance: AppearanceConfiguration
    var behavior: BehaviorConfiguration
    var search: SearchConfiguration
    var pinnedApplications: [String]      // bundle identifiers, ordered
    var onboarding: OnboardingState
}
```

Load sequence:

1. Read `Data`. Absent → defaults, `hasCompletedOnboarding = false`.
2. Decode `{ "version": Int }` only.
3. `version > currentVersion` → keep the raw data untouched, run defaults in memory, log a
   warning. A newer Nexus wrote it; do not clobber a downgrade.
4. `version < currentVersion` → apply `Migration` steps in order, each `(Int) -> (Data) throws -> Data`.
5. Decode the full struct. Any failure → copy the raw data to `configuration.corrupt.<ISO8601>`,
   fall back to defaults, log. **Never crash on bad configuration.**

Saves are debounced 250 ms and coalesced; each save publishes `.configurationChanged`.
`UserDefaults` (not a file in Application Support) because it is the native mechanism, gets
free atomicity and `defaults` CLI inspection during development, and the payload is kilobytes.

---

## 8. Logging (§66, §111.4.5)

`os.Logger`, subsystem `com.congbui.nexus`, one logger per category, all in `Log.swift`:

`Nexus.App`, `Nexus.Sidebar`, `Nexus.Search`, `Nexus.Windows`, `Nexus.Applications`,
`Nexus.System`, `Nexus.Permissions`. (`Nexus.Automation`, `Nexus.Plugins` reserved, unused
in the MVP.)

- Default level `.debug` in debug builds, `.info` in release.
- **Privacy:** file paths, window titles, and search queries are `\(value, privacy: .private)`.
  Bundle identifiers, counts, error codes are `.public` — they are what you actually need at
  3 a.m. Never log file contents, tokens, or command output.
- Latency budgets (§68) use `OSSignposter`, not log lines: search query, sidebar render,
  window enumeration.

---

## 9. Permissions as capabilities (§64, §111.2)

```swift
enum Permission: Sendable { case accessibility, screenRecording }
enum PermissionStatus: Sendable { case granted, denied, notDetermined }
```

- Accessibility: `AXIsProcessTrusted()` for status; `AXIsProcessTrustedWithOptions` with the
  prompt option **only** from an explicit user action, never at launch.
- Screen Recording: `CGPreflightScreenCaptureAccess()`; request via
  `CGRequestScreenCaptureAccess()` on explicit action only.
- Every feature declares `requiredPermission`. The UI asks the `PermissionService`, never the
  macOS API directly.
- Denial is a first-class state with a designed appearance, not an error alert. Milestones 1–3
  declare `nil` and must keep working with everything denied.

---

## 10. Error handling (§65)

`NexusError` is a small enum: `.permissionDenied(Permission)`, `.targetDisappeared`,
`.systemDenied(OSStatus)`, `.timedOut`.

- AX returning `kAXErrorInvalidUIElement` ⇒ `.targetDisappeared` ⇒ drop the item and emit
  `.windowClosed`. That is a normal state transition, not a failure.
- Every AX element gets `AXUIElementSetMessagingTimeout(element, 0.25)`. An unresponsive app
  is skipped and retried on its next event.
- No `try!`, no force unwraps outside tests. No `fatalError` outside programmer-error
  preconditions in pure logic.
- User-facing errors surface only for actions the user just took; background failures log
  and self-heal.

---

## 11. Testing (§67, §111.4.6)

Swift Testing (`import Testing`). Unit tests are the gate for every milestone:

- **Ranking** — pure function over `(query, candidate, frecency)`; the largest test surface.
- **String matching** — prefix, word-boundary, acronym, subsequence, Unicode, empty query.
- **Configuration** — round-trip, defaults, corrupt data, forward version, each migration step.
- **SearchEngine** — provider fan-out, cancellation of superseded queries, result merging,
  a provider that hangs, a provider that throws.
- **Frecency** — decay and ordering.
- **Services** — via injected fakes; no test touches the real AX API or launches applications.

Integration and UI tests are deliberately deferred (§67: "do not attempt to create a massive
test suite before the architecture stabilizes").

---

## 12. Extensibility without speculation (§32)

Three seams are deliberately open, because the vision sections need them and they cost nothing
now:

1. `SearchProvider` — new providers register with the engine; no UI change required.
2. `NexusActionDescriptor` — new cases add capabilities without changing the result model.
3. `NexusConfiguration` versioning — new settings groups without breaking existing users.

Everything else in §36–60 (workspaces, widgets, plugins, automation, AI) is **not** designed
for now. No plugin loader, no widget host, no rule engine, no abstraction with one
implementation waiting for a second.
