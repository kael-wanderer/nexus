import SwiftUI

/// The tabs of the settings window, as a value: the search results have to be able to say where a
/// setting lives, and to send the window there.
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general, dock, bar, appearance, behavior, shortcuts, search, permissions, about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .dock: return String(localized: "Dock")
        case .bar: return String(localized: "Bar")
        case .appearance: return String(localized: "Appearance")
        case .behavior: return String(localized: "Behavior")
        case .shortcuts: return String(localized: "Shortcuts")
        case .search: return String(localized: "Search")
        case .permissions: return String(localized: "Permissions")
        case .about: return String(localized: "About")
        }
    }

    public var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .dock: return "rectangle.bottomthird.inset.filled"
        case .bar: return "rectangle.grid.1x2"
        case .appearance: return "paintbrush"
        case .behavior: return "slider.horizontal.3"
        case .shortcuts: return "keyboard"
        case .search: return "magnifyingglass"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}

/// One row of the settings window, as something searchable: the label it carries, the words
/// somebody might go looking for it under, and the tab it is on.
public struct SettingsEntry: Identifiable, Hashable, Sendable {
    public let title: String
    /// Synonyms and near-misses — what the control is called elsewhere, or what it does. Searched
    /// alongside the title, never shown.
    public let keywords: String
    public let tab: SettingsTab

    public var id: String { "\(tab.rawValue).\(title)" }

    init(_ title: String, _ keywords: String = "", _ tab: SettingsTab) {
        self.title = title
        self.keywords = keywords
        self.tab = tab
    }
}

/// The index the settings search reads.
///
/// ponytail: hand-kept. SwiftUI cannot be asked what labels a view tree holds, so the alternative
/// is a parallel declarative settings model every pane is rebuilt on top of — far more code than
/// the list below. Add an entry when you add a control; `SettingsSearchTests` keeps every tab
/// represented, and no more than that.
public enum SettingsSearch {
    public static let entries: [SettingsEntry] = [
        // General
        SettingsEntry(String(localized: "Show Nexus in the menu bar"), "status item icon menubar", .general),
        SettingsEntry(String(localized: "Enable the global shortcut"), "hotkey keyboard palette", .general),
        SettingsEntry(String(localized: "Launch Nexus at login"), "startup login item auto start", .general),
        SettingsEntry(String(localized: "Run Setup Again…"), "onboarding wizard first run", .general),

        // Dock
        SettingsEntry(String(localized: "Nexus is"), "my dock replacement extra bar", .dock),
        SettingsEntry(String(localized: "macOS Dock"), "hidden visible system dock", .dock),
        SettingsEntry(String(localized: "Restore macOS Dock"), "bring back system dock", .dock),
        SettingsEntry(String(localized: "Display"), "screen monitor which display", .dock),

        // Bar
        SettingsEntry(String(localized: "Start menu button"), "launcher applications list", .bar),
        SettingsEntry(String(localized: "Opens from"), "start menu corner anchor", .bar),
        SettingsEntry(String(localized: "What is playing"), "now playing media music player", .bar),
        SettingsEntry(String(localized: "Running applications"), "open apps section", .bar),
        SettingsEntry(String(localized: "Minimized windows"), "minimised section", .bar),
        SettingsEntry(String(localized: "Window count badges"), "how many windows dots", .bar),
        SettingsEntry(String(localized: "Favourites"), "favorites pinned section", .bar),
        SettingsEntry(String(localized: "Hide over full-screen apps"), "fullscreen space", .bar),
        SettingsEntry(String(localized: "Show folder preview on hover"), "folder stack contents", .bar),
        SettingsEntry(String(localized: "Suggest groups by category"), "grouping suggestion", .bar),
        SettingsEntry(String(localized: "Group colours and emoji"), "colors tint emoji group", .bar),
        SettingsEntry(String(localized: "Most pinned rows"), "limit how many pinned", .bar),
        SettingsEntry(String(localized: "Most running rows"), "limit how many running", .bar),

        // Appearance
        SettingsEntry(String(localized: "Position"), "edge left right top bottom", .appearance),
        SettingsEntry(String(localized: "Sidebar width"), "how wide thickness", .appearance),
        SettingsEntry(String(localized: "Icon size"), "how big icons", .appearance),
        SettingsEntry(String(localized: "Icon spacing"), "gap between icons", .appearance),
        SettingsEntry(String(localized: "Corner radius"), "rounded corners", .appearance),
        SettingsEntry(String(localized: "Opacity"), "transparency translucency", .appearance),
        SettingsEntry(String(localized: "Media player"), "now playing style compact wide", .appearance),
        SettingsEntry(String(localized: "Wide player shows"), "artwork title controls", .appearance),

        // Behavior
        SettingsEntry(String(localized: "Auto-hide the sidebar"), "autohide slide away", .behavior),
        SettingsEntry(String(localized: "Hide delay"), "autohide timing seconds", .behavior),
        SettingsEntry(String(localized: "Expand on hover"), "grow widen", .behavior),
        SettingsEntry(String(localized: "Show window previews on hover"), "flyout thumbnails window list", .behavior),
        SettingsEntry(String(localized: "Hover delay"), "preview timing seconds", .behavior),
        SettingsEntry(String(localized: "Panel size"), "flyout now playing small medium large", .behavior),
        SettingsEntry(String(localized: "Keep windows off Nexus"), "reserved space struts", .behavior),
        SettingsEntry(String(localized: "Applications per group"), "group capacity 9 16", .behavior),
        SettingsEntry(String(localized: "Opened group shows"), "group layout icons list grid folder", .behavior),
        SettingsEntry(String(localized: "Clicking an icon"), "click behaviour launch activate window list", .behavior),

        // Shortcuts
        SettingsEntry(String(localized: "Open search"), "palette shortcut hotkey", .shortcuts),
        SettingsEntry(String(localized: "Keyboard access to the bar"), "focus keyboard navigation", .shortcuts),
        SettingsEntry(String(localized: "Focus the bar"), "shortcut hotkey bar", .shortcuts),
        SettingsEntry(String(localized: "Window switcher"), "alt tab switcher shortcut", .shortcuts),
        SettingsEntry(String(localized: "Open the switcher"), "shortcut hotkey switcher", .shortcuts),

        // Search
        SettingsEntry(String(localized: "In the bar, show"), "search box icon disabled style", .search),
        SettingsEntry(String(localized: "Search applications"), "scope apps", .search),
        SettingsEntry(String(localized: "Search windows"), "scope windows", .search),
        SettingsEntry(String(localized: "Search files"), "scope spotlight files", .search),
        SettingsEntry(String(localized: "Search actions"), "scope commands", .search),
        SettingsEntry(String(localized: "Maximum results"), "how many results limit", .search),

        // Permissions
        SettingsEntry(String(localized: "Accessibility"), "permission windows control ax", .permissions),
        SettingsEntry(String(localized: "Screen Recording"), "permission previews thumbnails", .permissions),

        // About
        SettingsEntry(String(localized: "Version"), "build number about", .about),
        SettingsEntry(String(localized: "Copy Version Details"), "diagnostics support", .about),
    ]

    /// Every token has to be somewhere in the entry — title, keywords or the tab's own name — so
    /// "group list" finds one row and not the eleven either word finds alone. Case- and
    /// accent-insensitive: nobody types "Favourites" with the right u in a hurry.
    public static func matches(_ query: String) -> [SettingsEntry] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }
        return entries.filter { entry in
            let haystack = "\(entry.title) \(entry.keywords) \(entry.tab.title)"
            return tokens.allSatisfy { token in
                haystack.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}

/// The results, as the settings window shows them while something is typed: what matched, and the
/// tab it will take you to.
struct SettingsSearchResults: View {
    let query: String
    let jump: (SettingsEntry) -> Void

    var body: some View {
        let results = SettingsSearch.matches(query)
        return Group {
            if results.isEmpty {
                VStack(spacing: 6) {
                    Text("No settings match “\(query)”")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { entry in
                    Button { jump(entry) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: entry.tab.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Text(entry.title)
                            Spacer(minLength: 8)
                            Text(entry.tab.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Settings search results"))
    }
}
