# Dock Habits and Row Motion (Weeks 2–3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make rows redraw only when their own state changes, give the bar the Dock's small motions, and add the three Dock gestures a person loses by switching to Nexus, so the owner can run with the system Dock replaced for two weeks.

**Architecture:** Each row view stops reading the shared view model in its `body` and receives one `Equatable` value, `RowState`, computed by its parent; SwiftUI then skips rows whose value did not change. Motion values live in `Design`. The three gestures are small additions to existing seams: `ApplicationServing` (hide, open files), `FolderStackService` (sort), and the AppKit drop catcher (file drops).

**Tech Stack:** Swift 6 (tools 6.0), macOS 14 floor, SwiftUI + AppKit, Swift Testing.

**Spec:** `docs/reviews/2026-11-15-feature-review.html` (Add 1, 2, 4; Improve 4) and `docs/design/2026-11-16-motion-and-menus-mockup.html` (motion values, the two menus).

**Depends on:** `2026-11-16-smooth-bar-week1.md` merged, and the owner's word that the bar is better.

**Branches:** `feat/row-motion` (Tasks 1–3), then `feat/dock-habits` (Tasks 4–7). Each merged to `main` with `--no-ff`. Do not push.

## Global Constraints

- Everything in the week 1 plan's Global Constraints applies unchanged: zero warnings, three test runs under load, `ScratchDefaults`, `waitUntil`, Reduce Motion gating, no dependency, no private API, no personal data in logs.
- New stored settings are additive keys read with `decodeIfPresent`, following the hand-written `init(from:)` in `NexusConfiguration.swift`. `NexusConfiguration.currentVersion` stays 5: no migration step.
- Anything dropped or decoded from outside is untrusted: file URLs only, at most 64 per drop, each must exist. Paths are never logged; log counts.
- User-visible strings go through `String(localized:)`, sentence style as in the existing menus.
- Each new behaviour gets a row in `docs/release-checklist.md` and a line in `CHANGELOG.md` under `Unreleased`.

## Review Focus

1. A drag reordering rows while a badge or a window count changes underneath: the dragged row must not snap back or lose its drop caret. Pinned by Task 1 test "a badge change touches only its own row's state".
2. A `.app` dropped on an application row: it pins, exactly as when dropped on a gap; it is not "opened with" the row's application. Pinned by Task 6 test "an application bundle dropped on a row is pinned".
3. A file dropped on an application that is not running: the application launches and opens the file. Pinned by Task 6 test "files open in a row's application whether or not it runs".
4. Hide Others when the row's application is itself hidden or has no windows: it comes forward, everything else hides, and Nexus's own panels stay. Pinned by Task 4 test "hide others spares the target and Nexus".
5. A stack folder holding thousands of files, sorted by date: still one directory read, still capped at 60, newest first. Pinned by Task 5 test "date order is applied before the limit".

---

### Task 1: Rows take a value, not the model

Today every `SidebarItemView` reads `model.appearance`, `model.behavior`, `model.focusedRowID`, `model.groupCandidate`, `model.draggingIdentifier`, `model.isEditing`, `model.badge(for:)`, `model.dropEdge(for:)`, `model.isLaunching(_:)` and `model.windowCountsAreExact` in its `body` (`SidebarView.swift:304-391`). Observation tracks by property read, so a change to any of them re-runs every row. During a drag that is every pointer move.

**Files:**
- Create: `Sources/NexusUI/Sidebar/RowState.swift`
- Modify: `Sources/NexusUI/Sidebar/SidebarView.swift` (`pinnedSection`, `section(_:)`, `minimizedSection`, `SidebarItemView`)
- Modify: `Sources/NexusUI/Sidebar/SidebarGroupView.swift`, `SidebarFolderView.swift`, `MinimizedWindowRow.swift` (same pattern)
- Modify: `Sources/NexusUI/Sidebar/SidebarViewModel.swift` (one function)
- Test: `Tests/NexusUITests/RowStateTests.swift`

**Interfaces:**
- Produces:
  ```swift
  /// Everything a row's body depends on besides its own item. Equatable, so a row whose state
  /// did not change is not redrawn.
  public struct RowState: Equatable, Sendable {
      public var iconSize: CGFloat
      public var rowHeight: CGFloat
      public var position: SidebarPosition
      public var expanded: Bool
      public var showsWindowCount: Bool      // behavior.showWindowCount && windowCountsAreExact
      public var badge: String?
      public var isLaunching: Bool
      public var isFocused: Bool
      public var isGroupCandidate: Bool
      public var isFileDropTarget: Bool      // always false until Task 6 sets it
      public var isDragging: Bool
      public var isEditing: Bool
      public var dropEdge: Bool?             // the existing return type of model.dropEdge(for:)
      public var isVertical: Bool { position.isVertical }
  }
  extension SidebarViewModel {
      public func rowState(for id: String) -> RowState
  }
  ```
- Changes: `SidebarItemView` becomes
  ```swift
  struct SidebarItemView: View, Equatable {
      let model: SidebarViewModel      // plain `let`, not @Bindable: used only inside closures
      let item: SidebarItem
      let state: RowState
      nonisolated static func == (l: Self, r: Self) -> Bool { l.item == r.item && l.state == r.state }
  }
  ```
  and every call site appends `.equatable()`.

**Decisions:**
- The parent (`pinnedSection`, `section`) calls `model.rowState(for: item.id)` for each row. The parent's body therefore reads everything and re-runs on any change; that is cheap, it builds structs. The children are what is expensive, and they are now skipped.
- **The rule inside a row's `body` and every computed property it calls: read `item` and `state` only, never `model`.** `model` may be touched only inside closures that run later: `onClick`, `menu`, the drag callbacks, `onHover`, `accessibilityAction`. A single `model.` read in `body` silently undoes the task.
- `SidebarGroupView`, `SidebarFolderView` and `MinimizedWindowRow` get the same shape with their own item type. For a group, `badge` is `model.badge(forGroup:)`.
- `IconCache.shared.icon(for:size:)` in `body` is fine: it is not observed state.
- `@State isHovered` and `bounced` stay in the row.

- [ ] **Step 1: Write the failing tests**

```swift
@Test("A badge change touches only its own row's state")
@MainActor func badgeIsLocal() async {
    let model = await makeModel(pinned: ["com.apple.Safari", "com.apple.Mail"])
    let before = (model.rowState(for: "com.apple.Safari"), model.rowState(for: "com.apple.Mail"))
    model.setBadges(["com.apple.Mail": "3"])
    #expect(model.rowState(for: "com.apple.Safari") == before.0)
    #expect(model.rowState(for: "com.apple.Mail") != before.1)
    #expect(model.rowState(for: "com.apple.Mail").badge == "3")
}

@Test("Keyboard focus moving one row changes two states and no others")
@MainActor func focusIsLocal() async {
    let model = await makeModel(pinned: ["a.one", "a.two", "a.three"])
    model.beginKeyboardNavigation()
    model.focusFirstRow()
    let before = ["a.one", "a.two", "a.three"].map { model.rowState(for: $0) }
    model.moveFocus(by: 1)
    let after = ["a.one", "a.two", "a.three"].map { model.rowState(for: $0) }
    #expect(zip(before, after).filter { $0 != $1 }.count == 2)
}

@Test("A drag marks the dragged row and the row under it, and nothing else")
@MainActor func dragIsLocal() async {
    let model = await makeModel(pinned: ["a.one", "a.two", "a.three"])
    let before = model.rowState(for: "a.three")
    model.beginDrag("a.one")
    model.dragMoved(over: "a.two", at: .trailingEdge)
    #expect(model.rowState(for: "a.one").isDragging)
    #expect(model.rowState(for: "a.two").dropEdge != nil)
    #expect(model.rowState(for: "a.three") == before)
}

@Test("Window counts show only when the setting is on and the counts are exact")
```

Use the model helper the neighbouring test files use (`SidebarPolishTests.swift`, `KeyboardNavigationTests.swift`) and their way of defining applications in `FakeApplicationService`; with a Start menu row first, `focusFirstRow` may land there, so switch that row off in the configuration the helper builds. `.trailingEdge` is the `CGPoint` extension in `FakeApplicationService.swift`.

- [ ] **Step 2: Run, expect failure** — `swift test --filter RowStateTests`; `rowState` does not exist.
- [ ] **Step 3: Implement `RowState` and `rowState(for:)`.**
- [ ] **Step 4: Convert `SidebarItemView`**, then the group, folder and minimized rows. After converting each, run `rg -n 'model\.' <file>` and confirm every hit is inside a closure.
- [ ] **Step 5: Add a guard test** that fails if the rule is broken again. In `RowStateTests.swift`, read `Sources/NexusUI/Sidebar/SidebarView.swift` from disk (path from `#filePath`), take the text of `struct SidebarItemView` up to its `private func click`, and `#expect` that between `var body: some View {` and the first `.onHover` there is no occurrence of `model.`. Crude, and it is what stops a later edit from undoing this quietly.
- [ ] **Step 6: Run everything** — `swift test && make lint`, then three runs under load.
- [ ] **Step 7: Commit** — `git commit -m "perf: rows redraw only when their own state changes"`

---

### Task 2: Row motion: press, launch hop, reorder spring

**Files:**
- Modify: `Sources/NexusUI/Design/DesignMetrics.swift`, `Sources/NexusUI/Sidebar/RowDecorations.swift:21-22`
- Modify: `Sources/NexusUI/Support/ContextMenuCatcher.swift` (`PanelRowInteraction`, `CatcherView`, `nexusRow`)
- Modify: `Sources/NexusUI/Sidebar/SidebarView.swift` (`SidebarItemView`, `SidebarGlyphRow`), and the group and folder rows
- Test: `Tests/NexusUITests/DesignTests.swift`

**Interfaces:**
- Produces in `Design`:
  ```swift
  public static let press = Animation.spring(duration: 0.18, bounce: 0)
  public static let pressScale: CGFloat = 0.92
  public static let hopUp = Animation.easeOut(duration: 0.20)
  public static let hopDown = Animation.easeIn(duration: 0.20)
  public static let launchBounce: CGFloat = 10      // was 7
  ```
  `Design.reveal` (a spring since week 1) is what reorders already use; `Design.bounce` is deleted.
- Produces: `nexusRow(…, onPressChange: ((Bool) -> Void)? = nil)`, forwarded through `PanelRowInteraction` to `CatcherView`.

**Decisions:**
- Press: `CatcherView.mouseDown` calls `onPressChange(true)`; `mouseUp`, the start of a drag, and a long press that enters edit mode call `onPressChange(false)`. The row keeps `@State private var isPressed` and applies `.scaleEffect(isPressed ? Design.pressScale : 1)` to the icon `ZStack` only (not the label), animated with `Design.press`. Reduce Motion: no scale.
- Launch hop: replace the one-shot `withAnimation(Design.bounce)` at `SidebarView.swift:370-374` with a hop that repeats for as long as `state.isLaunching` is true and stops at rest:
  ```swift
  .phaseAnimator([false, true], trigger: hopTrigger) { view, up in
      view.offset(up ? hopOffset : .zero)
  } animation: { up in up ? Design.hopUp : Design.hopDown }
  ```
  `hopOffset` is today's `bounceOffset` with `Design.launchBounce`, without the `bounced` flag. `hopTrigger` is an `Int` `@State`; a `.task(id: state.isLaunching)` increments it every 400 ms while launching and stops when the task is cancelled. Reduce Motion: no hop; the 0.45 opacity dimming stays.
- The hover highlight keeps `Design.hover` (ease-out, 0.12 s): colour changes do not need a spring.

- [ ] **Step 1: Write the failing tests** in `DesignTests.swift`: `Design.pressScale == 0.92`, `Design.launchBounce == 10`; and for the catcher, build a `PanelRowInteraction.CatcherView`, set `onPressChange`, send it `mouseDown` then `mouseUp` with synthesised `NSEvent`s (`NSEvent.mouseEvent(with:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:)`), and expect `[true, false]`. If the existing tests already synthesise clicks on the catcher, copy that; if `mouseDown` enters a tracking loop that cannot be driven from a test, extract the two calls into `func pressBegan()` / `func pressEnded()` and test those.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement** tokens, the catcher callback, the press scale, the hop.
- [ ] **Step 4: Run** `swift test && make lint`; three runs under load.
- [ ] **Step 5: Commit** — `git commit -m "feat: press feedback and a launch hop that lasts as long as the launch"`

---

### Task 3: Popovers fade

Every popover appears with `orderFrontRegardless()` and vanishes with `orderOut(nil)`: flyout, group, folder, player, volume, calendar (`PanelController.swift`, twelve call sites).

**Files:**
- Create: `Sources/NexusUI/Panels/PanelFade.swift`
- Modify: `Sources/NexusUI/Panels/PanelController.swift` (the show and hide functions of the six popovers; not the bars, not the edge triggers)
- Test: `Tests/NexusUITests/PanelFadeTests.swift`

**Interfaces:**
- Produces:
  ```swift
  @MainActor public final class PanelFade {
      public static let fadeIn: TimeInterval = 0.12
      public static let fadeOut: TimeInterval = 0.09
      public init(reduceMotion: @escaping () -> Bool)
      public func show(_ panel: NSPanel)
      public func hide(_ panel: NSPanel)
  }
  ```

**Decisions:**
- `show`: if the panel is not visible, `alphaValue = 0`, `orderFrontRegardless()`; then animate `animator().alphaValue = 1` over `fadeIn`. If it is already visible (switching rows with a flyout open), only make sure alpha is heading to 1: no flash.
- `hide`: animate alpha to 0 over `fadeOut`, then `orderOut(nil)` and reset `alphaValue = 1`.
- Each `show` and `hide` bumps a per-panel generation counter (`[ObjectIdentifier: Int]`). A hide's completion handler orders the panel out only if the generation is unchanged. This is the whole defence against "hide, then show 50 ms later, then the old hide's completion removes the panel".
- Reduce Motion: `show` orders front at alpha 1, `hide` orders out, both synchronously.
- Window alpha is animated by the window server; no view is laid out per frame.
- `removeOutsideClickMonitorIfIdle()` and the other code that tests `panel.isVisible` runs before the fade ends. Where a hide function checks visibility of the panel it has just hidden, check the model state it already has (`folderModel.folder`, `flyoutModel.target`, …) instead.

- [ ] **Step 1: Write the failing tests** with a plain borderless `NSPanel`:

```swift
@Test("Show then hide leaves the panel off screen")          // waitUntil !panel.isVisible; alphaValue == 1 afterwards
@Test("Hide then show at once leaves the panel on screen")   // hide, show, sleep 200 ms, isVisible && alphaValue == 1
@Test("Reduce motion shows and hides synchronously")         // no waiting; isVisible flips in the same turn
```

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement `PanelFade`**, one instance owned by `PanelController`, built with its `reduceMotion` closure from week 1.
- [ ] **Step 4: Replace the twelve call sites.** `rg -n 'orderFrontRegardless|orderOut' Sources/NexusUI/Panels/PanelController.swift` afterwards must show only the bars (`bars[…]`, `bar.`) and the edge triggers.
- [ ] **Step 5: Run** `swift test && make lint`; three runs under load. `WindowFlyoutTests`, `FolderStackUITests` and `SidebarGroupTests` may assert visibility straight after a hide: change those to `waitUntil`.
- [ ] **Step 6: Commit, merge** — `git commit -m "feat: popovers fade in and out"`, then merge `feat/row-motion` into `main` with `--no-ff`.

---

### Task 4: Hide, Hide Others, ⌥-click

**Files:**
- Modify: `Sources/NexusCore/Applications/ApplicationService.swift` (protocol and actor)
- Modify: `Tests/NexusUITests/FakeApplicationService.swift`
- Modify: `Sources/NexusUI/Sidebar/SidebarViewModel.swift` (near `quit`, line ~1549, and `activateOrLaunch`, line 664)
- Modify: `Sources/NexusUI/Sidebar/SidebarView.swift` (`contextMenuItems`, `click`)
- Test: `Tests/NexusUITests/SidebarViewModelTests.swift`

**Interfaces:**
- Produces on `ApplicationServing`:
  ```swift
  func hide(_ identity: ApplicationIdentity) async
  /// Hides every regular application except `identity` and this process.
  func hideOthers(except identity: ApplicationIdentity) async
  ```
- Produces on `SidebarViewModel`:
  ```swift
  public func hide(_ item: SidebarItem)
  public func hideOthers(_ item: SidebarItem)
  public func activateOrLaunch(_ item: SidebarItem, hidingPrevious: Bool)   // the existing one-argument form calls this with false
  ```
- `FakeApplicationService` records `hidden: [String]` and `hidOthersExcept: [String]`.

**Decisions:**
- `hide`: `NSRunningApplication.hide()` on every running instance with that bundle identifier, on the main actor through the existing `withRunningApplication` pattern.
- `hideOthers`: for each `NSWorkspace.shared.runningApplications` with `activationPolicy == .regular`, skip the target's bundle identifier and `Bundle.main.bundleIdentifier`, call `hide()`. Do not use `NSWorkspace.hideOtherApplications()`: it spares the *active* application, which is not the row's.
- Model `hideOthers(_:)`: activate the item, then hide the others.
- `hidingPrevious: true`: read the frontmost application's identity before activating; after activation succeeds, hide it, unless it is the item itself or Nexus. The model needs the frontmost identity: add `@ObservationIgnored public var frontmostApplication: () -> ApplicationIdentity? = { … NSWorkspace.shared.frontmostApplication … }` so tests can inject it.
- `click()` in `SidebarItemView` passes `hidingPrevious: NSEvent.modifierFlags.contains(.option)`.
- Menu, for a running application, directly after "Show All Windows": `Hide`, then `Hide Others`. Not shown for an application that is not running. See the mockup.

- [ ] **Step 1: Write the failing tests**

```swift
@Test("Hide hides the row's application")                          // fake.hidden == ["com.apple.Safari"]
@Test("Hide others spares the target and Nexus")                   // fake.activated contains target; fake.hidOthersExcept == [target]
@Test("Option-click hides the application being left")             // frontmostApplication = Mail; activateOrLaunch(safari, hidingPrevious: true); waitUntil fake.hidden == ["com.apple.Mail"]
@Test("Option-click on the frontmost application hides nothing")   // frontmost == item; sleep 100 ms; fake.hidden.isEmpty
@Test("A plain click hides nothing")
```

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement** protocol, actor, fake, model, menu, click.
- [ ] **Step 4: Run** `swift test && make lint`.
- [ ] **Step 5: Commit** — `git commit -m "feat: Hide, Hide Others and option-click"`

---

### Task 5: Newest first in a folder stack

**Files:**
- Modify: `Sources/NexusCore/System/FolderStackService.swift`
- Modify: `Sources/NexusCore/Configuration/NexusConfiguration.swift` (`BehaviorConfiguration`: field, coding key, `init(from:)`)
- Modify: `Sources/NexusUI/Sidebar/FolderStackView.swift` (`FolderStackViewModel.read`), `SidebarFolderView.swift` (menu, line ~89), `SidebarViewModel.swift` (setter), `Sources/NexusApp/Composition.swift` if `read` is wired there
- Test: `Tests/NexusCoreTests/FolderStackTests.swift`, `ConfigurationTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum FolderSort: String, Codable, Sendable, CaseIterable { case name, dateAdded }
  extension FolderSort {
      /// Downloads is useful because the newest file is on top; everything else reads by name.
      public static func defaultSort(forPath path: String,
                                     downloads: String = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "") -> FolderSort
  }
  public struct FolderItem { …; public var dateAdded: Date? }        // new field, defaulted nil in init
  public static func list(_ url: URL, limit: Int = limit, sort: FolderSort = .name) -> FolderListing
  static func sorted(_ items: [FolderItem], by sort: FolderSort) -> [FolderItem]
  // BehaviorConfiguration
  public var folderSort: [String: FolderSort] = [:]                  // keyed by the folder's stored path
  public func sort(forFolder path: String) -> FolderSort            // stored value, else FolderSort.defaultSort
  // SidebarViewModel
  public func setSort(_ sort: FolderSort, forFolder path: String)
  ```

**Decisions:**
- Request `.addedToDirectoryDateKey` and `.creationDateKey` alongside the existing keys; `dateAdded` is the first, falling back to the second.
- `.dateAdded` order: newest first; no folders-first grouping; items with no date last; ties broken by name with `localizedStandardCompare`. `.name` order is today's, unchanged.
- Sort before `prefix(limit)`.
- An unknown raw value in stored `folderSort` must not fail the whole configuration: decode the dictionary as `[String: String]` and keep the entries that map to a case.
- Unpinning a folder removes its entry from `folderSort`.
- Folder row menu: after "Show Contents", a submenu `Sort By` with `Name` and `Date Added`, the current one ticked. See the mockup.
- No row in Settings: the choice belongs to the stack.

- [ ] **Step 1: Write the failing tests**

```swift
@Test("By date: newest first, folders not grouped, undated last")
func dateOrder() {
    let d = Date(timeIntervalSince1970: 1_000)
    let items = [
        FolderItem(url: URL(fileURLWithPath: "/t/old.txt"), name: "old.txt", isDirectory: false, dateAdded: d),
        FolderItem(url: URL(fileURLWithPath: "/t/dir"), name: "dir", isDirectory: true, dateAdded: d.addingTimeInterval(50)),
        FolderItem(url: URL(fileURLWithPath: "/t/none"), name: "none", isDirectory: false, dateAdded: nil),
        FolderItem(url: URL(fileURLWithPath: "/t/new.txt"), name: "new.txt", isDirectory: false, dateAdded: d.addingTimeInterval(100)),
    ]
    #expect(FolderStackService.sorted(items, by: .dateAdded).map(\.name) == ["new.txt", "dir", "old.txt", "none"])
    #expect(FolderStackService.sorted(items, by: .name).map(\.name) == ["dir", "new.txt", "none", "old.txt"])
}

@Test("Date order is applied before the limit")       // temp dir, 5 files with creation dates set via FileManager.setAttributes; list(limit: 2, sort: .dateAdded) returns the two newest
@Test("Downloads defaults to date added, anything else to name")
func defaults() {
    #expect(FolderSort.defaultSort(forPath: "/Users/x/Downloads", downloads: "/Users/x/Downloads") == .dateAdded)
    #expect(FolderSort.defaultSort(forPath: "/Users/x/Documents", downloads: "/Users/x/Downloads") == .name)
}
@Test("A stored sort survives a round trip; an unknown value is dropped, not fatal")
// decode {"folderSort": {"/a": "dateAdded", "/b": "bySize"}} into BehaviorConfiguration → ["/a": .dateAdded]
@Test("A configuration written before this key existed still loads")   // existing fixture, folderSort == [:]
@Test("Unpinning a folder forgets its sort")
```

The temporary directory comes from `FileManager.default.temporaryDirectory` plus a UUID, removed in a `defer`.

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement** the service, the configuration field, the model setter, `read`, the menu.
- [ ] **Step 4: Run** `swift test && make lint`.
- [ ] **Step 5: Commit** — `git commit -m "feat: folder stacks sort by date added; Downloads does by default"`

---

### Task 6: Drop a file on an application to open it

Row catchers register only Nexus's own row type (`ContextMenuCatcher.swift:157-163`), so a file dragged over a row falls through to `BarHostingView`, which pins it or refuses.

**Files:**
- Modify: `Sources/NexusCore/Applications/ApplicationService.swift`, `Tests/NexusUITests/FakeApplicationService.swift`
- Modify: `Sources/NexusUI/Support/ContextMenuCatcher.swift` (`CatcherView` destination methods, `registerDropTypes`, `PanelRowInteraction`, `nexusRow`)
- Modify: `Sources/NexusUI/Sidebar/SidebarViewModel.swift`, `RowState.swift` (the `isFileDropTarget` value), `SidebarView.swift` (`SidebarItemView` only)
- Test: `Tests/NexusUITests/SidebarViewModelTests.swift`, `Tests/NexusUITests/SidebarPolishTests.swift`

**Interfaces:**
- Produces on `ApplicationServing`: `func open(_ urls: [URL], with identity: ApplicationIdentity) async throws`
- Produces on `SidebarViewModel`:
  ```swift
  public static let maximumDroppedFiles = 64
  public private(set) var fileDropTarget: String?
  public func fileDragChanged(over id: String?)                       // sets or clears fileDropTarget
  /// true when the drop was used.
  @discardableResult public func filesDropped(_ urls: [URL], on item: SidebarItem) -> Bool
  ```
- Produces on `nexusRow`: `onFileDrag: ((Bool) -> Void)? = nil`, `onFileDrop: (([URL]) -> Bool)? = nil`.
- `FakeApplicationService` records `opened: [(urls: [URL], with: String)]`.

**Decisions:**
- `ApplicationService.open`: `NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration:)` with `activates = true`; the application URL from `urlForApplication(withBundleIdentifier:)`; throws `NexusError.notFound` when there is none. Works whether or not the application is running.
- `filesDropped` validation, in this order; any failure returns `false`:
  1. `urls` is not empty and has at most `maximumDroppedFiles` entries.
  2. Every URL is a file URL (`isFileURL`).
  3. Every URL exists (`FileManager.default.fileExists(atPath:)`).
- Then: if **any** URL has the path extension `app` (case-insensitive), hand the whole list to the existing `pinApplications(at:)` and return its result: a dropped application is a pin wherever on the bar it lands. Otherwise open them with the row's application and return `true`.
- `CatcherView`: when `onFileDrop` is set, register `[.fileURL]` in addition to the row type. In `draggingEntered` and `draggingUpdated`: a pasteboard carrying the row type is handled first, exactly as today; otherwise, if it carries file URLs, call `onFileDrag(true)` and return `.copy`. `draggingExited` and `draggingEnded` call `onFileDrag(false)`. `performDragOperation` for file URLs reads them with `readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])`, the same call `BarHostingView.urls(from:)` makes, and returns `onFileDrop(urls)`.
- Only application rows get `onFileDrop`. Group, folder, minimized and glyph rows keep today's behaviour.
- The row under a file drag shows the same 2 pt tinted outline the group candidate uses (`SidebarView.swift:350-356`), driven by `state.isFileDropTarget`.
- Logging: `Log.sidebar.notice("Opened \(count) dropped file(s) with \(bundleIdentifier)")`, both `privacy: .public`. Never the paths.

- [ ] **Step 1: Write the failing tests**

```swift
@Test("Files open in a row's application whether or not it runs")
// temp file; filesDropped([file], on: notRunningItem) == true; waitUntil fake.opened.count == 1; opened[0].with == item.id
@Test("An application bundle dropped on a row is pinned")
// temp dir named "Fake.app"; define it in the fake; filesDropped → fake.opened.isEmpty, model.pinned gains a row
@Test("More than 64 files are refused")                 // 65 existing temp files → false, fake.opened.isEmpty
@Test("A URL that is not a file is refused")            // URL(string: "https://example.com/a.pdf")! → false
@Test("A file that does not exist is refused")          // → false
@Test("An empty drop is refused")
@Test("A file drag marks only the row under it")        // fileDragChanged(over: a) → rowState(a).isFileDropTarget, rowState(b) unchanged; fileDragChanged(over: nil) clears
```

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement** service, fake, model, catcher, row.
- [ ] **Step 4: Run** `swift test && make lint`; three runs under load. `SidebarPolishTests` covers row drags: all of it must still pass untouched.
- [ ] **Step 5: Update `FEATURES.md`**: it lists this gesture as out of scope; move it to the feature list.
- [ ] **Step 6: Commit** — `git commit -m "feat: drop a file on an application to open it there"`

---

### Task 7: ⌥Tab as the switcher's default, release notes, and the trial

**Files:**
- Modify: `Sources/NexusCore/Configuration/NexusConfiguration.swift:115-120`
- Modify: every place that names the old default: `rg -n '⌃⌥W|windowSwitcherDefault' Sources Tests README.md FEATURES.md docs/release-checklist.md docs/design/window-switcher.md site-content`
- Modify: `CHANGELOG.md`, `docs/release-checklist.md`, `Resources/Info.plist` (version)
- Test: `Tests/NexusCoreTests/ConfigurationTests.swift`

**Decisions:**
- `windowSwitcherDefault = KeyboardShortcut(keyCode: 48, modifiers: optionKey)` (48 is `kVK_Tab`). Update the doc comment.
- A stored configuration that names a shortcut keeps it; one that stored an explicit `null` keeps the switcher off; only a configuration with no key at all gets the new default. The hand-written decoder already separates the three cases: confirm with tests, change nothing else.
- Version: `CFBundleShortVersionString` 0.3.0, build number one above the current. Do not tag; the owner tags after the checklist.

- [ ] **Step 1: Write the failing tests**

```swift
@Test("The default switcher shortcut is option-tab")
func defaultIsOptionTab() {
    #expect(KeyboardShortcut.windowSwitcherDefault == KeyboardShortcut(keyCode: 48, modifiers: KeyboardShortcut.optionKey))
    #expect(GeneralConfiguration().windowSwitcherShortcut == .windowSwitcherDefault)
}
@Test("A stored control-option-W is kept")        // decode {"windowSwitcherShortcut": {"keyCode": 13, "modifiers": 6144}} → unchanged
@Test("A stored null keeps the switcher off")     // → nil
```
(6144 is `controlKey | optionKey`, 0x1000 | 0x0800.)

- [ ] **Step 2: Run, expect the first to fail.**
- [ ] **Step 3: Change the constant and every mention.**
- [ ] **Step 4: Checklist rows** in `docs/release-checklist.md` for Tasks 1–7:
  - Drag a row along a bar of 20 or more applications: rows slide under the drag without stutter.
  - Press and hold an icon: it shrinks slightly; release: it springs back.
  - Launch a slow application: its icon hops until the application appears, then rests.
  - Hover a running application, then the next: the flyout fades in once and does not flash between rows.
  - Open and close each of the six popovers quickly, twice: none stays on screen, none fails to appear.
  - Row menu: Hide; Hide Others; ⌥-click another application hides the one being left.
  - Downloads stack: the newest file is first. Change to Name and back from the row menu; the choice survives a relaunch.
  - Drop a PDF on Preview's row: it opens there. On an application that is not running: it launches and opens. Drop an application on a row: it is pinned.
  - Fresh configuration: ⌥Tab opens the switcher. Existing configuration with another shortcut: unchanged.
- [ ] **Step 5: `CHANGELOG.md`**: rename `Unreleased` to `0.3.0`, with the week 1 lines and one line per task here.
- [ ] **Step 6: Run** `swift test && make lint`; three runs under load; `make app`.
- [ ] **Step 7: Commit and merge** — `git commit -am "feat: option-tab default; 0.3.0 notes and checklist"`, merge `feat/dock-habits` into `main` with `--no-ff`.
- [ ] **Step 8: Repeat the stall measurement** (week 1 plan, Task 1 Step 6) and add `## Stall result, 0.3.0` to `docs/verification.md`.
- [ ] **Step 9: Report to the owner and stop.** Nothing below is for an agent.

## The trial (owner)

1. `make install`, run `docs/release-checklist.md` on the installed build. Failing rows come back for a fix plan.
2. Turn Dock replacement on. Use the Mac normally for 14 days.
3. Keep a three-column note: date, what made you reach for the system Dock, what felt slow or wrong.
4. On day 14, one of:
   - **Still on, note mostly empty:** tag 0.3.0, publish, and take up the removals and the 0.4.0 items in the feature review.
   - **Still on, note has a clear list:** that list is the next plan.
   - **Turned off before day 14:** stop work on the bar. Decide whether the window switcher and the search palette are worth keeping as a smaller tool; the note says why the bar lost.

## Not in this plan

- The eleven removals, calculator, settings export, update check: feature review, after the trial.
- Magnification, the genie effect, anything that imitates the Dock's own look.
- Icon pre-rendering: only if the 0.3.0 stall result shows stalls while scrolling.
