import Foundation

/// Where the app points a person at the user guide.
///
/// The guide's pages live in `docs/guide/` and are published under `base`. A page's raw value is
/// its slug, permanent once published, so a link in an installed build keeps working after the
/// guide is edited. `GuideContentTests` fails if any slug here is missing from `guide.json`.
public enum GuideLink {
    /// The only host the app links to for the guide.
    public static let base: URL = {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "kael.io.vn"
        parts.path = "/projects/nexus/docs"
        return parts.url ?? URL(filePath: "/")
    }()

    public enum Page: String, CaseIterable, Sendable {
        case home = ""
        case install = "start-here/install"
        case firstFiveMinutes = "start-here/first-five-minutes"
        case replaceTheDock = "recipes/replace-the-dock"
        case search = "search/search"
        case windowSwitcher = "windows/window-switcher"
        case settings = "reference/settings"
        case keyboardShortcuts = "reference/keyboard-shortcuts"
        case privacyAndPermissions = "reference/privacy-and-permissions"
        case troubleshooting = "reference/troubleshooting"
    }

    public static func url(_ page: Page) -> URL {
        page == .home ? base : base.appending(path: page.rawValue)
    }
}
