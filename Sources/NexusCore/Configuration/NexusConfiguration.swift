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

public enum DisplayPreference: Codable, Sendable, Equatable {
    case main
    case withMouse
    case specific(String)   // display UUID (D11)
}

public struct DisplayOverride: Codable, Sendable, Equatable {
    public var position: SidebarPosition?
    public var width: Double?
    public init(position: SidebarPosition? = nil, width: Double? = nil) {
        self.position = position
        self.width = width
    }
}

public struct KeyboardShortcut: Codable, Sendable, Equatable, Hashable {
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
    public init() {}

    /// Tolerant like `NexusConfiguration`'s: a synthesised decoder treats a missing key as an
    /// error, so adding a field would silently reset every other field in the section on the
    /// first launch after an upgrade (D67).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        globalShortcutEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalShortcutEnabled) ?? true
        showStartMenu = try container.decodeIfPresent(Bool.self, forKey: .showStartMenu) ?? false
    }
}

public struct AppearanceConfiguration: Codable, Sendable, Equatable {
    public var position: SidebarPosition = .left
    public var width: Double = 64            // 44...120
    public var iconSize: Double = 40         // 24...96
    public var iconSpacing: Double = 8       // 0...24
    public var cornerRadius: Double = 16     // 0...32
    public var opacity: Double = 1.0         // 0.3...1.0
    public var display: DisplayPreference = .main
    public var perDisplay: [String: DisplayOverride] = [:]
    public var startMenuCorner: StartMenuCorner = .bottomLeading
    public init() {}

    public static let widthRange: ClosedRange<Double> = 44...120
    public static let iconSizeRange: ClosedRange<Double> = 24...96
    public static let iconSpacingRange: ClosedRange<Double> = 0...24
    public static let cornerRadiusRange: ClosedRange<Double> = 0...32
    public static let opacityRange: ClosedRange<Double> = 0.3...1.0

    /// Tolerant decode: a key added in a later version must not reset the rest (D67).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decodeIfPresent(SidebarPosition.self, forKey: .position) ?? .left
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 64
        iconSize = try container.decodeIfPresent(Double.self, forKey: .iconSize) ?? 40
        iconSpacing = try container.decodeIfPresent(Double.self, forKey: .iconSpacing) ?? 8
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 16
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        display = try container.decodeIfPresent(DisplayPreference.self, forKey: .display) ?? .main
        perDisplay = try container.decodeIfPresent([String: DisplayOverride].self, forKey: .perDisplay) ?? [:]
        startMenuCorner = try container.decodeIfPresent(StartMenuCorner.self, forKey: .startMenuCorner) ?? .bottomLeading
    }

    /// Values arriving from a decoded file or a future migration are clamped rather than trusted.
    public mutating func clamp() {
        width = width.clamped(to: Self.widthRange)
        iconSize = iconSize.clamped(to: Self.iconSizeRange)
        iconSpacing = iconSpacing.clamped(to: Self.iconSpacingRange)
        cornerRadius = cornerRadius.clamped(to: Self.cornerRadiusRange)
        opacity = opacity.clamped(to: Self.opacityRange)
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
    public var showWindowCount = true
    public var showFavorites = true
    /// Keep other applications' windows off the bar (M12). Off by default: it moves windows
    /// belonging to other applications, which is not something to do to somebody unasked.
    public var reserveSpace = false
    public var clickBehavior: ClickBehavior = .activateOrLaunch
    public var reduceMotionOverride: Bool?
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
        showWindowCount = try container.decodeIfPresent(Bool.self, forKey: .showWindowCount) ?? true
        showFavorites = try container.decodeIfPresent(Bool.self, forKey: .showFavorites) ?? true
        reserveSpace = try container.decodeIfPresent(Bool.self, forKey: .reserveSpace) ?? false
        clickBehavior = try container.decodeIfPresent(ClickBehavior.self, forKey: .clickBehavior) ?? .activateOrLaunch
        reduceMotionOverride = try container.decodeIfPresent(Bool.self, forKey: .reduceMotionOverride)
    }

    public mutating func clamp() {
        autoHideDelay = autoHideDelay.clamped(to: 0.1...5)
        hoverPreviewDelay = hoverPreviewDelay.clamped(to: Self.hoverPreviewDelayRange)
    }
}

public struct SearchConfiguration: Codable, Sendable, Equatable {
    public var shortcut = KeyboardShortcut.optionSpace
    public var searchApplications = true
    public var searchWindows = true
    public var searchFiles = true
    public var searchActions = true
    public var maximumResults = 20
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
    public static let currentVersion = 1

    public var version: Int = currentVersion
    public var general = GeneralConfiguration()
    public var appearance = AppearanceConfiguration()
    public var behavior = BehaviorConfiguration()
    public var search = SearchConfiguration()
    public var pinnedApplications: [String] = []
    /// User-chosen order for the running-but-unpinned section. Only the applications the user has
    /// actually moved appear here; everything else stays alphabetical, after them.
    public var runningApplicationOrder: [String] = []
    public var frecency: [String: FrecencyEntry] = [:]
    public var onboarding = OnboardingState()
    public var dock = DockConfiguration()

    public init() {}

    /// Decoding is tolerant: every field has a default, so a partial payload written by an older
    /// build still loads. Ranges are clamped afterwards.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        general = try container.decodeIfPresent(GeneralConfiguration.self, forKey: .general) ?? .init()
        appearance = try container.decodeIfPresent(AppearanceConfiguration.self, forKey: .appearance) ?? .init()
        behavior = try container.decodeIfPresent(BehaviorConfiguration.self, forKey: .behavior) ?? .init()
        search = try container.decodeIfPresent(SearchConfiguration.self, forKey: .search) ?? .init()
        pinnedApplications = try container.decodeIfPresent([String].self, forKey: .pinnedApplications) ?? []
        runningApplicationOrder = try container.decodeIfPresent([String].self, forKey: .runningApplicationOrder) ?? []
        frecency = try container.decodeIfPresent([String: FrecencyEntry].self, forKey: .frecency) ?? [:]
        onboarding = try container.decodeIfPresent(OnboardingState.self, forKey: .onboarding) ?? .init()
        dock = try container.decodeIfPresent(DockConfiguration.self, forKey: .dock) ?? .init()
        appearance.clamp()
        behavior.clamp()
    }
}
