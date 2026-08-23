import AppKit
import Foundation

// MARK: - Applications

public struct ApplicationSearchProvider: SearchProvider {
    public let identifier = SearchProviderID.application
    public let category = SearchCategory.application

    private let index: ApplicationIndexSnapshot
    private let runningBundleIdentifiers: @Sendable () -> Set<String>

    public init(
        index: ApplicationIndexSnapshot,
        runningBundleIdentifiers: @escaping @Sendable () -> Set<String>
    ) {
        self.index = index
        self.runningBundleIdentifiers = runningBundleIdentifiers
    }

    public func results(for query: SearchQuery, context: SearchContext) async -> [SearchResult] {
        let running = runningBundleIdentifiers()
        return index.read().compactMap { application in
            guard let matchScore = StringMatch.score(query: query.trimmed, candidate: application.name)
            else { return nil }
            let id = "app:\(application.identity.bundleIdentifier)"
            let isRunning = running.contains(application.identity.bundleIdentifier)
            return SearchResult(
                id: id,
                title: application.name,
                subtitle: isRunning ? String(localized: "Application · running") : String(localized: "Application"),
                icon: .application(application.bundleURL),
                category: .application,
                score: Ranking.score(
                    matchScore: matchScore,
                    category: .application,
                    frecencyBoost: context.frecency.boost(for: id, now: context.now),
                    isRunning: isRunning,
                    belongsToFrontmostApplication: false
                ),
                action: .launchApplication(application.identity.bundleIdentifier),
                isRunning: isRunning,
                secondaryAction: .openFile(application.bundleURL)
            )
        }
    }
}

// MARK: - Windows

public struct WindowSearchProvider: SearchProvider {
    public let identifier = SearchProviderID.window
    public let category = SearchCategory.window
    /// Yields nothing when Accessibility is denied; the rest of search is unaffected.
    public let requiredPermission: Permission? = .accessibility

    private let windows: @Sendable () async -> [NexusWindow]

    public init(windows: @escaping @Sendable () async -> [NexusWindow]) {
        self.windows = windows
    }

    public func results(for query: SearchQuery, context: SearchContext) async -> [SearchResult] {
        await windows().compactMap { window in
            let label = "\(window.applicationName) — \(window.title)"
            let best = max(
                StringMatch.score(query: query.trimmed, candidate: window.title) ?? 0,
                StringMatch.score(query: query.trimmed, candidate: label) ?? 0
            )
            guard best > 0 else { return nil }
            let isFrontmost = window.identity.owner.bundleIdentifier == context.frontmostApplication
            let id = "window:\(window.id)"
            return SearchResult(
                id: id,
                title: label,
                subtitle: String(localized: "Window"),
                icon: .symbol(window.isMinimized ? "minus.rectangle" : "macwindow"),
                category: .window,
                score: Ranking.score(
                    matchScore: best,
                    category: .window,
                    frecencyBoost: context.frecency.boost(for: id, now: context.now),
                    isRunning: true,
                    belongsToFrontmostApplication: isFrontmost
                ),
                action: .activateWindow(window.identity),
                isRunning: true
            )
        }
    }
}

// MARK: - Files

public struct FileSearchProvider: SearchProvider {
    public let identifier = SearchProviderID.file
    public let category = SearchCategory.file
    /// The only debounced provider (D7): Spotlight is expensive and answers asynchronously.
    public let debounce = Duration.milliseconds(120)
    public let minimumCharacters = 2

    private let run: @Sendable (String, Int, FileKind) async -> [MetadataItem]

    public init(
        run: @escaping @Sendable (String, Int, FileKind) async -> [MetadataItem] = { text, limit, kind in
            await MetadataQueryRunner.shared.run(
                .displayNamePrefix(text, kind: kind),
                scope: .userHome,
                limit: limit
            )
        }
    ) {
        self.run = run
    }

    public func results(for query: SearchQuery, context: SearchContext) async -> [SearchResult] {
        let text = query.trimmed
        let items = await run(text, SearchCategory.file.resultCap * 4, query.scope.fileKind)

        return items.compactMap { item in
            guard let matchScore = StringMatch.score(query: text, candidate: item.displayName)
            else { return nil }
            let id = "file:\(item.url.path)"
            return SearchResult(
                id: id,
                title: item.displayName,
                subtitle: item.url.deletingLastPathComponent().path
                    .replacingOccurrences(
                        of: FileManager.default.homeDirectoryForCurrentUser.path,
                        with: "~"
                    ),
                icon: .file(item.url),
                category: .file,
                score: Ranking.score(
                    matchScore: matchScore,
                    category: .file,
                    frecencyBoost: context.frecency.boost(for: id, now: context.now),
                    isRunning: false,
                    belongsToFrontmostApplication: false
                ),
                action: .openFile(item.url),
                secondaryAction: .openURL(item.url.deletingLastPathComponent())
            )
        }
    }
}

// MARK: - Actions

public struct ActionSearchProvider: SearchProvider {
    public let identifier = SearchProviderID.action
    public let category = SearchCategory.action

    private let runningApplications: @Sendable () -> [(name: String, bundleIdentifier: String)]
    /// The panes of System Settings, injected so tests do not read the machine's own copy of
    /// macOS. Read once and cached by `SettingsPaneIndex`.
    private let settingsPanes: @Sendable () -> [SettingsPane]

    public init(
        runningApplications: @escaping @Sendable () -> [(name: String, bundleIdentifier: String)],
        settingsPanes: @escaping @Sendable () -> [SettingsPane] = { SettingsPaneIndex.shared }
    ) {
        self.runningApplications = runningApplications
        self.settingsPanes = settingsPanes
    }

    public func results(for query: SearchQuery, context: SearchContext) async -> [SearchResult] {
        typealias Candidate = (
            id: String, title: String, subtitle: String, symbol: String, action: NexusActionDescriptor
        )
        let actionSubtitle = String(localized: "Action")
        var candidates: [Candidate] = BuiltInAction.allCases.map {
            ("action:\($0.rawValue)", $0.title, actionSubtitle, $0.symbol, .runBuiltInAction($0))
        }
        for application in runningApplications() {
            candidates.append((
                "action:quit:\(application.bundleIdentifier)",
                String(localized: "Quit \(application.name)"),
                actionSubtitle,
                "xmark.circle",
                .quitApplication(application.bundleIdentifier)
            ))
        }
        // A pane of System Settings is a thing you go looking for by name — "displays", "sound" —
        // and opening one is what the Settings scope always claimed to do (M19, finished).
        let settingsSubtitle = String(localized: "System Settings")
        for pane in settingsPanes() {
            guard let url = pane.url else { continue }
            candidates.append((
                "settings:\(pane.id)", pane.name, settingsSubtitle, "gearshape", .openURL(url)
            ))
        }

        return candidates.compactMap { candidate in
            guard let matchScore = StringMatch.score(query: query.trimmed, candidate: candidate.title)
            else { return nil }
            return SearchResult(
                id: candidate.id,
                title: candidate.title,
                subtitle: candidate.subtitle,
                icon: .symbol(candidate.symbol),
                category: .action,
                score: Ranking.score(
                    matchScore: matchScore,
                    category: .action,
                    frecencyBoost: context.frecency.boost(for: candidate.id, now: context.now),
                    isRunning: false,
                    belongsToFrontmostApplication: false
                ),
                action: candidate.action
            )
        }
    }
}
