import Foundation
import Observation

// Ported from Bugler (`Sources/Bugler/Core/UpdateFeed.swift` and `AlertWatchers.swift`), same
// author. Nexus never downloads, replaces or restarts itself: an update is a version number and a
// release page, and the person decides.

/// The version string compared against the feed: `0.3.0-build.3`.
///
/// The build number is a numeric SemVer prerelease identifier, so builds of one version order
/// numerically while a semantic bump still wins. The feed publishes the same shape; a bare
/// `0.3.0` would outrank every build of itself.
public enum AppFeedVersion {
    public static func string(shortVersion: String?, build: String?) -> String {
        let trimmed = shortVersion?.trimmingCharacters(in: .whitespaces) ?? ""
        // "0" rather than "": a version nothing can parse is silently never newer than anything.
        let version = trimmed.isEmpty ? "0" : trimmed
        guard let build = build?.trimmingCharacters(in: .whitespaces),
            let number = Int(build), number >= 0
        else { return version }
        return "\(version)-build.\(number)"
    }

    public static func string(bundle: Bundle = .main) -> String {
        string(
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}

/// Which builds the person is offered.
public enum UpdateChannel: String, CaseIterable, Codable, Sendable {
    case stable
    case beta

    public var label: String {
        switch self {
        case .stable: return String(localized: "Stable")
        case .beta: return String(localized: "Beta")
        }
    }

    /// An unknown stored value resolves to Stable.
    public static func resolve(_ stored: String?) -> UpdateChannel {
        guard let stored, let channel = UpdateChannel(rawValue: stored) else { return .stable }
        return channel
    }
}

/// One entry in the feed: a version and its browser-openable release page.
public struct UpdateFeedEntry: Equatable, Sendable {
    public let version: String
    public let releaseURL: URL?
}

/// The decoded `latest.json`: a required stable entry and an optional beta one.
public struct UpdateFeed: Equatable, Sendable {
    public let stable: UpdateFeedEntry
    public let beta: UpdateFeedEntry?
}

/// The class of a failed check. No message, path or URL: only what kind of failure it was.
public enum UpdateFeedFailure: String, Equatable, Sendable {
    case notFound = "not_found"
    case serverError = "server_error"
    case timeout
    case malformed
    case transport
}

public enum UpdateFeedResult: Equatable, Sendable {
    case success(UpdateFeed)
    case unavailable(UpdateFeedFailure)
}

extension UpdateFeed {
    /// Pure status + body classification, so every branch is testable without a network.
    public static func decode(status: Int, data: Data) -> UpdateFeedResult {
        switch status {
        case 200:
            guard RemoteJSON.isAcceptable(data) else { return .unavailable(.malformed) }
            guard let feed = try? JSONDecoder().decode(Wire.self, from: data),
                !feed.version.isEmpty
            else { return .unavailable(.malformed) }
            return .success(feed.model)
        case 404:
            return .unavailable(.notFound)
        default:
            return .unavailable(.serverError)
        }
    }

    struct Wire: Decodable {
        let version: String
        let releaseURL: String?
        let beta: BetaWire?

        struct BetaWire: Decodable {
            let version: String
            let releaseURL: String?
            enum CodingKeys: String, CodingKey {
                case version
                case releaseURL = "release_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case version
            case releaseURL = "release_url"
            case beta
        }

        /// Only `https`. The release URL ends up at `NSWorkspace.open`, which would launch a local
        /// application for a `file:` URL or hand a custom scheme to another app. A rejected URL
        /// leaves the update with no link, so it is not offered.
        static func webURL(_ raw: String?) -> URL? {
            guard let raw, let url = URL(string: raw), url.scheme == "https", url.host != nil
            else { return nil }
            return url
        }

        var model: UpdateFeed {
            UpdateFeed(
                stable: UpdateFeedEntry(version: version, releaseURL: Self.webURL(releaseURL)),
                beta: beta.flatMap { entry in
                    entry.version.isEmpty
                        ? nil
                        : UpdateFeedEntry(version: entry.version, releaseURL: Self.webURL(entry.releaseURL))
                }
            )
        }
    }
}

/// Fetches and classifies the feed, bounded in time and size.
public enum UpdateFeedFetcher {
    /// Published by the Bug Apps site for every release of Nexus.
    public static let feedURL: URL = {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "kael.io.vn"
        parts.path = "/projects/nexus/latest.json"
        return parts.url ?? URL(filePath: "/")
    }()

    public static func fetch(url: URL = UpdateFeedFetcher.feedURL) async -> UpdateFeedResult {
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.httpShouldHandleCookies = false
        guard let (data, response) = await RemoteFetch.body(for: request) else {
            return .unavailable(.transport)
        }
        return UpdateFeed.decode(status: response.statusCode, data: data)
    }
}

/// One offered update: a newer version and the exact page to open.
public struct UpdateAvailable: Equatable, Sendable {
    public let version: String
    public let releaseURL: URL

    public init(version: String, releaseURL: URL) {
        self.version = version
        self.releaseURL = releaseURL
    }

    /// `0.4.0-build.5` reads as `0.4.0 (5)`, the way About shows the running build.
    public var displayVersion: String {
        guard let range = version.range(of: "-build.") else { return version }
        return "\(version[..<range.lowerBound]) (\(version[range.upperBound...]))"
    }
}

/// The newest eligible entry strictly newer than the running build. Beta counts only on the Beta
/// channel and only when it beats stable, so a beta user still gets a newer stable release.
public enum UpdateSelection {
    public static func pick(feed: UpdateFeed, currentVersion: String, channel: UpdateChannel)
        -> UpdateAvailable?
    {
        var best = feed.stable
        if channel == .beta, let beta = feed.beta, SemVer.isNewer(beta.version, than: best.version) {
            best = beta
        }
        guard SemVer.isNewer(best.version, than: currentVersion) else { return nil }
        guard let url = best.releaseURL else { return nil }
        return UpdateAvailable(version: best.version, releaseURL: url)
    }
}

/// The update check, shared by Settings › About and the menu-bar menu.
///
/// Checks on launch and once a day while Nexus runs, when automatic checks are on; the button in
/// About checks on demand either way. An offer is shown, never installed: About and the menu-bar
/// menu open the release page in the browser.
@MainActor
@Observable
public final class UpdateChecker {
    public enum State: Equatable, Sendable {
        case idle
        case checking
        case unavailable(UpdateFeedFailure)
        case upToDate
        case update(UpdateAvailable)
    }

    public static let interval: Duration = .seconds(24 * 60 * 60)

    public private(set) var state: State = .idle

    @ObservationIgnored private let currentVersion: () -> String
    @ObservationIgnored private let channel: () -> UpdateChannel
    @ObservationIgnored private let isAutomatic: () -> Bool
    @ObservationIgnored private let fetch: () async -> UpdateFeedResult
    @ObservationIgnored private var loop: Task<Void, Never>?

    public init(
        currentVersion: @escaping () -> String = { AppFeedVersion.string() },
        channel: @escaping () -> UpdateChannel,
        isAutomatic: @escaping () -> Bool,
        fetch: @escaping () async -> UpdateFeedResult = { await UpdateFeedFetcher.fetch() }
    ) {
        self.currentVersion = currentVersion
        self.channel = channel
        self.isAutomatic = isAutomatic
        self.fetch = fetch
    }

    /// Launch check plus a daily one. Each pass asks `isAutomatic` again, so switching automatic
    /// checks off stops the network traffic without restarting anything. Idempotent.
    public func startAutomaticChecks() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if let self, self.isAutomatic() { await self.checkNow() }
                do { try await Task.sleep(for: Self.interval) } catch { return }
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// The button's entry point.
    public func check() {
        guard state != .checking else { return }
        Task { await checkNow() }
    }

    public func checkNow() async {
        guard state != .checking else { return }
        state = .checking
        switch await fetch() {
        case .unavailable(let failure):
            state = .unavailable(failure)
        case .success(let feed):
            if let update = UpdateSelection.pick(feed: feed, currentVersion: currentVersion(), channel: channel()) {
                state = .update(update)
            } else {
                state = .upToDate
            }
        }
    }

    public var offeredUpdate: UpdateAvailable? {
        if case .update(let update) = state { return update }
        return nil
    }

    /// What the button says. A failure says **Retry**, never "up to date": a check that did not
    /// happen must not read as one that succeeded.
    public var buttonLabel: String {
        switch state {
        case .idle: return String(localized: "Check Now")
        case .checking: return String(localized: "Checking…")
        case .unavailable: return String(localized: "Retry")
        case .upToDate: return String(localized: "Up to Date")
        case .update(let update): return String(localized: "Get \(update.displayVersion)")
        }
    }

    /// Why a check could not be made, in the person's terms.
    public var failureText: String? {
        guard case .unavailable(let failure) = state else { return nil }
        switch failure {
        case .timeout, .transport:
            return String(localized: "Nexus could not reach the update feed. Check your connection.")
        case .notFound, .serverError:
            return String(localized: "The update feed is not answering right now. Try again later.")
        case .malformed:
            return String(localized: "The update feed could not be read, so no version was compared.")
        }
    }
}
