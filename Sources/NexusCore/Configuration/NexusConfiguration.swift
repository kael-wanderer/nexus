import Foundation

public enum SidebarPosition: String, Codable, Sendable, CaseIterable {
    case left
    case right
    case top
    case bottom

    /// Vertical edges stack rows top-to-bottom; horizontal edges lay them out left-to-right.
    /// Every piece of layout maths branches on this and nothing else.
    public var isVertical: Bool { self == .left || self == .right }

    /// The edge the macOS Dock is parked on while Dock Replacement Mode is active. Sharing an
    /// edge would put the Dock's hot corner underneath Nexus's own edge trigger.
    public var opposite: SidebarPosition {
        switch self {
        case .left: .right
        case .right: .left
        case .top: .bottom
        case .bottom: .top
        }
    }
}

/// How much of the bar the media player takes (M17).
public enum MediaWidth: String, Codable, Sendable, CaseIterable {
    /// Two tiles: artwork with a progress line on it, and the transport buttons.
    case compact
    /// Four tiles: a small icon, the progress bar or the track name, and the buttons, all inline.
    case wide
}

/// What the wide player spends its middle on.
public enum MediaContent: String, Codable, Sendable, CaseIterable {
    case progress
    case title
}

/// Which corner the start menu opens from.
public enum StartMenuCorner: String, Codable, Sendable, CaseIterable {
    case bottomLeading
    case bottomTrailing
    case topLeading
    case topTrailing
}

public enum ClickBehavior: String, Codable, Sendable, CaseIterable {
    case activateOrLaunch
    case showWindowList
}

/// How the switcher's grid is divided up (M25).
public enum WindowSwitcherGrouping: String, Codable, Sendable, CaseIterable {
    case flat
    case application
    case display
}

/// What orders the switcher's cards (M25). `recent` is the order applications were last
/// activated, which is the order a switcher is normally reached for.
public enum WindowSwitcherSort: String, Codable, Sendable, CaseIterable {
    case recent
    case application
    case title
}

/// How big the two hover flyouts draw themselves — the window cards, and the now-playing panel.
/// One setting for both, because they are one visual family (`design/…/FlyoutPanel.swift`); the
/// per-case metrics live there, next to the views that read them.
public enum FlyoutSize: String, Codable, Sendable, CaseIterable {
    case small
    case medium
    case large
}

/// How a group's applications are laid out when the group is opened (M13): the icon grid, or a
/// list a long group is easier to read down.
public enum GroupLayout: String, Codable, Sendable, CaseIterable {
    case icons
    case list
}

public enum DisplayPreference: Codable, Sendable, Equatable {
    case main
    case withMouse
    case specific(String)   // display UUID (D11)
    /// A bar on every attached display, all showing the same thing (D91).
    case everyDisplay

    /// Whether this preference puts a bar on more than one screen, which is what decides whether
    /// the panels are kept in sync as displays come and go.
    public var isEveryDisplay: Bool { self == .everyDisplay }
}

public struct KeyboardShortcut: Codable, Sendable, Equatable, Hashable {
    /// `⌃⌥Space` — beside the palette's `⌥Space`, and free.
    ///
    /// `⌃F3` was the obvious choice, since that is what macOS uses to put the keyboard on the
    /// Dock. It registers and then never fires: the system owns it and consumes the key before a
    /// Carbon hotkey ever sees it, whether or not the Dock is hidden (D101).
    public static let focusBarDefault = KeyboardShortcut(
        keyCode: 49,                                     // Space
        modifiers: controlKey | optionKey
    )

    /// Carbon virtual key code; identical to `NSEvent.keyCode`.
    public var keyCode: UInt32
    /// Carbon modifier mask (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // Carbon constants, restated so NexusCore does not have to import Carbon.
    public static let cmdKey: UInt32 = 0x0100
    public static let shiftKey: UInt32 = 0x0200
    public static let optionKey: UInt32 = 0x0800
    public static let controlKey: UInt32 = 0x1000
    public static let spaceKeyCode: UInt32 = 49   // kVK_Space

    public static let optionSpace = KeyboardShortcut(keyCode: spaceKeyCode, modifiers: optionKey)
    public static let commandSpace = KeyboardShortcut(keyCode: spaceKeyCode, modifiers: cmdKey)

    /// `⌃⌥W` — the window switcher (M25). `⌥Space` is the palette and `⌃⌥Space` is the bar (D101);
    /// `⌘Tab` and `⌃↓` belong to the system and never reach a Carbon hotkey.
    public static let windowSwitcherDefault = KeyboardShortcut(
        keyCode: 13,                                     // kVK_ANSI_W
        modifiers: controlKey | optionKey
    )

    public var isCommandSpace: Bool { self == .commandSpace }

    /// At least one non-shift modifier is required; modifier-only combinations are rejected (§5).
    public var isValid: Bool {
        modifiers & (Self.cmdKey | Self.optionKey | Self.controlKey) != 0
    }
}

public struct FrecencyEntry: Codable, Sendable, Equatable {
    public var count: Int
    public var lastUsed: Date

    public init(count: Int = 0, lastUsed: Date = .distantPast) {
        self.count = count
        self.lastUsed = lastUsed
    }
}

public struct GeneralConfiguration: Codable, Sendable, Equatable {
    public var launchAtLogin = false
    public var showInMenuBar = true
    public var globalShortcutEnabled = true
    /// An addition, not a replacement for the palette — off until asked for (M11).
    public var showStartMenu = false
    /// Puts the keyboard on the bar (M23). `nil` switches it off. Default `⌃⌥Space` — `⌃F3`, the
    /// shortcut macOS uses for its own Dock, is owned by the system and never reaches us (D101).
    public var focusBarShortcut: KeyboardShortcut? = .focusBarDefault
    /// The now-playing row in the bar's tail (M15). Off by default, and its row gives its slot back
    /// to the applications when it is off (D74).
    public var showNowPlaying = false
    /// The window switcher's shortcut (M25). `nil` switches the feature off entirely — there is no
    /// other way in, by design: a switcher reached with the pointer is the bar.
    public var windowSwitcherShortcut: KeyboardShortcut? = .windowSwitcherDefault
    public init() {}

    // Written out because `encode(to:)` is now hand-written too (to give `windowSwitcherShortcut`
    // an explicit null instead of an omitted key); once both halves of `Codable` are provided,
    // Swift stops synthesising `CodingKeys` for either of them.
    private enum CodingKeys: String, CodingKey {
        case launchAtLogin, showInMenuBar, globalShortcutEnabled, showStartMenu
        case focusBarShortcut, showNowPlaying, windowSwitcherShortcut
    }

    /// Tolerant like `NexusConfiguration`'s: a synthesised decoder treats a missing key as an
    /// error, so adding a field would silently reset every other field in the section on the
    /// first launch after an upgrade (D67).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        globalShortcutEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalShortcutEnabled) ?? true
        showStartMenu = try container.decodeIfPresent(Bool.self, forKey: .showStartMenu) ?? false
        // Same "absent vs. explicit null" disambiguation as `windowSwitcherShortcut` below: a bare
        // `decodeIfPresent ?? default` cannot tell "never written" (upgrade, use the default) apart
        // from "written as null" (the user switched the bar off, honour that), which is why
        // `encode(to:)` writes this key unconditionally too.
        focusBarShortcut = container.contains(.focusBarShortcut)
            ? try container.decode(KeyboardShortcut?.self, forKey: .focusBarShortcut)
            : .focusBarDefault
        // A stored ⌃F3 is the old default, which macOS eats. Nobody chose it deliberately: it was
        // shipped as a default for one build, so it is replaced rather than honoured (D101).
        if focusBarShortcut == KeyboardShortcut(keyCode: 99, modifiers: KeyboardShortcut.controlKey) {
            focusBarShortcut = .focusBarDefault
        }
        showNowPlaying = try container.decodeIfPresent(Bool.self, forKey: .showNowPlaying) ?? false
        // `decodeIfPresent(_:forKey:) ?? default` cannot tell "key absent" (an upgrade, fall back
        // to the default) apart from "key present and explicitly null" (the user switched the
        // shortcut off, honour that) — both decode to Swift `nil`. `contains` disambiguates, which
        // is why `encode(to:)` below writes the key even when its value is nil.
        windowSwitcherShortcut = container.contains(.windowSwitcherShortcut)
            ? try container.decode(KeyboardShortcut?.self, forKey: .windowSwitcherShortcut)
            : .windowSwitcherDefault
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(showInMenuBar, forKey: .showInMenuBar)
        try container.encode(globalShortcutEnabled, forKey: .globalShortcutEnabled)
        try container.encode(showStartMenu, forKey: .showStartMenu)
        // Written unconditionally, not with `encodeIfPresent`: that omits the key entirely for
        // `nil`, which is indistinguishable on decode from a field an older build never wrote at
        // all. Writing an explicit null keeps "switched off" persisting as "switched off" rather
        // than reverting to the default on the next load — same reasoning as
        // `windowSwitcherShortcut` below, and it was a bug that this one lagged behind it.
        try container.encode(focusBarShortcut, forKey: .focusBarShortcut)
        try container.encode(showNowPlaying, forKey: .showNowPlaying)
        try container.encode(windowSwitcherShortcut, forKey: .windowSwitcherShortcut)
    }
}

public struct AppearanceConfiguration: Codable, Sendable, Equatable {
    public var position: SidebarPosition = .left
    public var width: Double = 64            // 44...120
    /// 64, the size of a macOS Dock tile at its default: an icon in a dock replacement that is
    /// smaller than the dock it replaces reads as a downgrade (D79).
    public var iconSize: Double = 64         // 24...96
    public var iconSpacing: Double = 8       // 0...24
    public var cornerRadius: Double = 16     // 0...32
    public var opacity: Double = 1.0         // 0.3...1.0
    public var display: DisplayPreference = .main
    public var startMenuCorner: StartMenuCorner = .bottomLeading
    /// How many rows each section of the bar shows before it scrolls inside itself (M14). Counted
    /// in rows, so a group counts once — which is what makes groups worth having.
    ///
    /// **Zero means "as many as the screen holds"**, which is the default: the bar grows until it
    /// runs out of edge and only then scrolls. A number is a ceiling on top of that, never a
    /// promise — the screen still wins.
    public var pinnedLimit = 0
    public var runningLimit = 0
    /// The media player's width, and what it fills it with (M17). A narrow vertical bar is always
    /// compact whatever this says — four tiles of *height* cannot hold a scrubber worth dragging.
    public var mediaWidth: MediaWidth = .wide
    public var mediaContent: MediaContent = .progress
    public init() {}

    public static let widthRange: ClosedRange<Double> = 44...120
    /// Zero is "fit the screen"; anything else is a ceiling.
    public static let rowLimitRange: ClosedRange<Int> = 0...40
    public static let iconSizeRange: ClosedRange<Double> = 24...96
    public static let iconSpacingRange: ClosedRange<Double> = 0...24
    public static let cornerRadiusRange: ClosedRange<Double> = 0...32
    public static let opacityRange: ClosedRange<Double> = 0.3...1.0

    /// Tolerant decode: a key added in a later version must not reset the rest (D67).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decodeIfPresent(SidebarPosition.self, forKey: .position) ?? .left
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 64
        iconSize = try container.decodeIfPresent(Double.self, forKey: .iconSize) ?? 64
        iconSpacing = try container.decodeIfPresent(Double.self, forKey: .iconSpacing) ?? 8
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 16
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        display = try container.decodeIfPresent(DisplayPreference.self, forKey: .display) ?? .main
        startMenuCorner = try container.decodeIfPresent(StartMenuCorner.self, forKey: .startMenuCorner) ?? .bottomLeading
        pinnedLimit = try container.decodeIfPresent(Int.self, forKey: .pinnedLimit) ?? 0
        runningLimit = try container.decodeIfPresent(Int.self, forKey: .runningLimit) ?? 0
        mediaWidth = try container.decodeIfPresent(MediaWidth.self, forKey: .mediaWidth) ?? .wide
        mediaContent = try container.decodeIfPresent(MediaContent.self, forKey: .mediaContent) ?? .progress
    }

    /// Values arriving from a decoded file or a future migration are clamped rather than trusted.
    public mutating func clamp() {
        width = width.clamped(to: Self.widthRange)
        iconSize = iconSize.clamped(to: Self.iconSizeRange)
        iconSpacing = iconSpacing.clamped(to: Self.iconSpacingRange)
        cornerRadius = cornerRadius.clamped(to: Self.cornerRadiusRange)
        opacity = opacity.clamped(to: Self.opacityRange)
        pinnedLimit = min(max(pinnedLimit, Self.rowLimitRange.lowerBound), Self.rowLimitRange.upperBound)
        runningLimit = min(max(runningLimit, Self.rowLimitRange.lowerBound), Self.rowLimitRange.upperBound)
    }
}

public struct BehaviorConfiguration: Codable, Sendable, Equatable {
    public var autoHide = false
    public var autoHideDelay: Double = 0.4
    public var hoverExpand = true
    /// Hovering an application opens its window flyout (M10).
    public var hoverPreview = true
    /// How long the pointer must rest on a row first. Long enough that sweeping the bar opens
    /// nothing, short enough that resting on a row feels immediate.
    public var hoverPreviewDelay: Double = 0.5
    public var showRunningApplications = true
    /// The windows that have been minimized, in the tail before Trash (M22).
    public var showMinimizedWindows = true
    public var showWindowCount = true
    public var showFavorites = true
    /// Keep other applications' windows off the bar (M12). Off by default: it moves windows
    /// belonging to other applications, which is not something to do to somebody unasked.
    public var reserveSpace = false
    /// How many applications fit in one group: 9 as a 3×3 grid, 16 as 4×4 (M13).
    public var groupCapacity = 9
    /// Hovering a pinned folder shows what is in it, without a click (M24). On, because a stack you
    /// have to click is a folder in the Finder with extra steps.
    public var folderHoverPreview = true
    /// Offer to put a newly pinned application into the group its category already has (M24). Off:
    /// moving somebody's dock around unasked is not a favour (D109).
    public var suggestCategoryGroups = false
    /// A group may carry a colour and an emoji (D108). On — it costs nothing until one is picked.
    public var groupColorsAndEmoji = true
    /// The bar steps aside on a display showing a full-screen space (D111). On: full screen means
    /// full screen, which is what the real Dock does.
    public var hideOverFullScreen = true
    public var clickBehavior: ClickBehavior = .activateOrLaunch
    public var reduceMotionOverride: Bool?
    /// How the switcher opened last time (M25). Remembered rather than reset, because a grouping is
    /// a way of working, not a one-off.
    public var windowSwitcherGrouping: WindowSwitcherGrouping = .flat
    public var windowSwitcherSort: WindowSwitcherSort = .recent
    public var windowSwitcherSortReversed = false
    /// Off skips ScreenCaptureKit entirely: icons only, and no permission ever asked for.
    public var windowSwitcherThumbnails = true
    /// How big the window flyout's cards and the now-playing panel draw themselves.
    public var flyoutSize: FlyoutSize = .medium
    /// Icons or a list inside an opened group (M13).
    public var groupLayout: GroupLayout = .icons
    public init() {}

    public static let hoverPreviewDelayRange: ClosedRange<Double> = 0.2...1.5

    /// Tolerant decode: a key added in a later version must not reset the rest (D67).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoHide = try container.decodeIfPresent(Bool.self, forKey: .autoHide) ?? false
        autoHideDelay = try container.decodeIfPresent(Double.self, forKey: .autoHideDelay) ?? 0.4
        hoverExpand = try container.decodeIfPresent(Bool.self, forKey: .hoverExpand) ?? true
        hoverPreview = try container.decodeIfPresent(Bool.self, forKey: .hoverPreview) ?? true
        hoverPreviewDelay = try container.decodeIfPresent(Double.self, forKey: .hoverPreviewDelay) ?? 0.5
        showRunningApplications = try container.decodeIfPresent(Bool.self, forKey: .showRunningApplications) ?? true
        showMinimizedWindows = try container.decodeIfPresent(Bool.self, forKey: .showMinimizedWindows) ?? true
        showWindowCount = try container.decodeIfPresent(Bool.self, forKey: .showWindowCount) ?? true
        showFavorites = try container.decodeIfPresent(Bool.self, forKey: .showFavorites) ?? true
        reserveSpace = try container.decodeIfPresent(Bool.self, forKey: .reserveSpace) ?? false
        groupCapacity = try container.decodeIfPresent(Int.self, forKey: .groupCapacity) ?? 9
        folderHoverPreview = try container.decodeIfPresent(Bool.self, forKey: .folderHoverPreview) ?? true
        suggestCategoryGroups = try container.decodeIfPresent(Bool.self, forKey: .suggestCategoryGroups) ?? false
        groupColorsAndEmoji = try container.decodeIfPresent(Bool.self, forKey: .groupColorsAndEmoji) ?? true
        hideOverFullScreen = try container.decodeIfPresent(Bool.self, forKey: .hideOverFullScreen) ?? true
        clickBehavior = try container.decodeIfPresent(ClickBehavior.self, forKey: .clickBehavior) ?? .activateOrLaunch
        reduceMotionOverride = try container.decodeIfPresent(Bool.self, forKey: .reduceMotionOverride)
        windowSwitcherGrouping = try container.decodeIfPresent(
            WindowSwitcherGrouping.self,
            forKey: .windowSwitcherGrouping
        ) ?? .flat
        windowSwitcherSort = try container.decodeIfPresent(WindowSwitcherSort.self, forKey: .windowSwitcherSort) ?? .recent
        windowSwitcherSortReversed = try container.decodeIfPresent(Bool.self, forKey: .windowSwitcherSortReversed) ?? false
        windowSwitcherThumbnails = try container.decodeIfPresent(Bool.self, forKey: .windowSwitcherThumbnails) ?? true
        flyoutSize = try container.decodeIfPresent(FlyoutSize.self, forKey: .flyoutSize) ?? .medium
        groupLayout = try container.decodeIfPresent(GroupLayout.self, forKey: .groupLayout) ?? .icons
    }

    public static let groupCapacities = [9, 16]

    public mutating func clamp() {
        autoHideDelay = autoHideDelay.clamped(to: 0.1...5)
        hoverPreviewDelay = hoverPreviewDelay.clamped(to: Self.hoverPreviewDelayRange)
        if !Self.groupCapacities.contains(groupCapacity) { groupCapacity = 9 }
    }
}

/// How the bar draws its Search part.
public enum SearchBarStyle: String, Codable, Sendable, CaseIterable {
    /// One slot, a magnifying glass. Clicking it opens the palette in the middle of the screen.
    case icon
    /// Three slots, drawn as a search box. Clicking it opens the palette beside the box.
    ///
    /// It is a box, not a field: this panel can never become key, so a real `NSTextField` here
    /// could not be typed into (`design/mvp.md` §2.1). Every keystroke belongs to the palette.
    case field
    /// No slot at all. The palette still opens on its shortcut; the bar just does not offer it.
    case disabled

    public var title: String {
        switch self {
        case .icon: String(localized: "An icon")
        case .field: String(localized: "A search box")
        case .disabled: String(localized: "Nothing")
        }
    }
}

public struct SearchConfiguration: Codable, Sendable, Equatable {
    public var shortcut = KeyboardShortcut.optionSpace
    public var searchApplications = true
    public var searchWindows = true
    public var searchFiles = true
    public var searchActions = true
    public var maximumResults = 20
    /// What the bar's Search part looks like: a single icon, or a box three slots wide that reads
    /// as a search field. The box opens the palette beside itself; the global shortcut always
    /// opens it in the middle of the screen, the way Spotlight does (D90).
    public var barStyle = SearchBarStyle.icon
    public init() {}

    /// Tolerant decode: a key added in a later version must not reset the rest (D67).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shortcut = try container.decodeIfPresent(KeyboardShortcut.self, forKey: .shortcut) ?? .optionSpace
        searchApplications = try container.decodeIfPresent(Bool.self, forKey: .searchApplications) ?? true
        searchWindows = try container.decodeIfPresent(Bool.self, forKey: .searchWindows) ?? true
        searchFiles = try container.decodeIfPresent(Bool.self, forKey: .searchFiles) ?? true
        searchActions = try container.decodeIfPresent(Bool.self, forKey: .searchActions) ?? true
        maximumResults = try container.decodeIfPresent(Int.self, forKey: .maximumResults) ?? 20
        barStyle = try container.decodeIfPresent(SearchBarStyle.self, forKey: .barStyle) ?? .icon
    }
}

/// The user's `com.apple.dock` settings as they were before Nexus touched them.
///
/// Every field is optional on purpose: a key that was never set has to be *deleted* on restore,
/// not written back as `false` or `0`. Writing a value the user never had is a silent settings
/// change, and it is the difference between "restored" and "close enough".
public struct DockSnapshot: Codable, Sendable, Equatable {
    public var autohide: Bool?
    public var autohideDelay: Double?
    public var autohideTimeModifier: Double?
    public var orientation: String?
    public var capturedAt: Date

    public init(
        autohide: Bool? = nil,
        autohideDelay: Double? = nil,
        autohideTimeModifier: Double? = nil,
        orientation: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.autohide = autohide
        self.autohideDelay = autohideDelay
        self.autohideTimeModifier = autohideTimeModifier
        self.orientation = orientation
        self.capturedAt = capturedAt
    }
}

public struct DockConfiguration: Codable, Sendable, Equatable {
    /// What the user asked for.
    public var replacementEnabled = false
    /// Whether Nexus's settings are currently written to `com.apple.dock`. Diverges from
    /// `replacementEnabled` only when a run ended without restoring — a crash, or `SIGKILL`.
    public var applied = false
    public var snapshot: DockSnapshot?
    public init() {}
}

public struct OnboardingState: Codable, Sendable, Equatable {
    public var hasCompleted = false
    public var completedVersion = 0
    public init() {}
}

public struct NexusConfiguration: Codable, Sendable, Equatable {
    /// 5 since Milestone 21: the dock's entries can be folders. Additive, but a downgrade has to
    /// see a version it does not know rather than an entry it cannot decode.
    public static let currentVersion = 5

    public var version: Int = currentVersion
    public var general = GeneralConfiguration()
    public var appearance = AppearanceConfiguration()
    public var behavior = BehaviorConfiguration()
    public var search = SearchConfiguration()
    /// The dock: applications and groups, in the order they are drawn.
    public var pinnedEntries: [DockEntry] = []
    /// User-chosen order for the running-but-unpinned section. Only the applications the user has
    /// actually moved appear here; everything else stays alphabetical, after them.
    public var runningApplicationOrder: [String] = []
    public var frecency: [String: FrecencyEntry] = [:]
    public var onboarding = OnboardingState()
    public var dock = DockConfiguration()

    public init() {}

    /// Every pinned application, groups flattened, in dock order. Read-only: writing it would
    /// have to decide what happens to the groups, and every caller that means "replace the dock
    /// with these applications" says so with `setPinnedApplications`.
    public var pinnedApplications: [String] {
        pinnedEntries.flatMap(\.applications)
    }

    public mutating func setPinnedApplications(_ identifiers: [String]) {
        pinnedEntries = identifiers.map { .application($0) }
    }

    public func group(withID id: UUID) -> ApplicationGroup? {
        pinnedEntries.compactMap(\.group).first { $0.id == id }
    }

    /// Spelled out because `encode(to:)` below is custom, which suppresses the synthesised keys.
    private enum CodingKeys: String, CodingKey {
        case version
        case general
        case appearance
        case behavior
        case search
        case pinnedEntries
        case runningApplicationOrder
        case frecency
        case onboarding
        case dock
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case pinnedApplications
    }

    /// Decoding is tolerant: every field has a default, so a partial payload written by an older
    /// build still loads. Ranges are clamped afterwards.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        general = try container.decodeIfPresent(GeneralConfiguration.self, forKey: .general) ?? .init()
        appearance = try container.decodeIfPresent(AppearanceConfiguration.self, forKey: .appearance) ?? .init()
        behavior = try container.decodeIfPresent(BehaviorConfiguration.self, forKey: .behavior) ?? .init()
        search = try container.decodeIfPresent(SearchConfiguration.self, forKey: .search) ?? .init()
        pinnedEntries = try container.decodeIfPresent([DockEntry].self, forKey: .pinnedEntries) ?? []
        // A v1 payload that reached here without its migration — a hand-written one, say — still
        // finds its dock rather than losing it.
        if pinnedEntries.isEmpty,
           let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
               .decodeIfPresent([String].self, forKey: .pinnedApplications) {
            pinnedEntries = legacy.map { .application($0) }
        }
        runningApplicationOrder = try container.decodeIfPresent([String].self, forKey: .runningApplicationOrder) ?? []
        frecency = try container.decodeIfPresent([String: FrecencyEntry].self, forKey: .frecency) ?? [:]
        onboarding = try container.decodeIfPresent(OnboardingState.self, forKey: .onboarding) ?? .init()
        dock = try container.decodeIfPresent(DockConfiguration.self, forKey: .dock) ?? .init()
        appearance.clamp()
        behavior.clamp()
        pinnedEntries = pinnedEntries.repaired(capacity: behavior.groupCapacity)
    }

    /// Writes the v1 `pinnedApplications` key alongside the entries. Nothing reads it; it is there
    /// so downgrading to a build that only knows v1 finds its dock instead of an empty bar.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(general, forKey: .general)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(behavior, forKey: .behavior)
        try container.encode(search, forKey: .search)
        try container.encode(pinnedEntries, forKey: .pinnedEntries)
        try container.encode(runningApplicationOrder, forKey: .runningApplicationOrder)
        try container.encode(frecency, forKey: .frecency)
        try container.encode(onboarding, forKey: .onboarding)
        try container.encode(dock, forKey: .dock)

        var legacy = encoder.container(keyedBy: LegacyCodingKeys.self)
        try legacy.encode(pinnedApplications, forKey: .pinnedApplications)
    }
}
