import Foundation
import Testing

@testable import NexusCore

@Suite("Update feed")
struct UpdateFeedTests {
    private static let https = URL(string: "https://kael.io.vn/api/download/releases/x")!

    private static func feed(_ json: String, status: Int = 200) -> UpdateFeedResult {
        UpdateFeed.decode(status: status, data: Data(json.utf8))
    }

    // MARK: Versions

    @Test func feedVersionAppendsTheBuildNumber() {
        #expect(AppFeedVersion.string(shortVersion: "0.3.0", build: "3") == "0.3.0-build.3")
        #expect(AppFeedVersion.string(shortVersion: "0.3.0", build: "dev") == "0.3.0")
        #expect(AppFeedVersion.string(shortVersion: nil, build: "3") == "0-build.3")
    }

    @Test func buildsOrderNumericallyAndARealBumpWins() {
        #expect(SemVer.isNewer("0.3.0-build.10", than: "0.3.0-build.9"))
        #expect(SemVer.isNewer("0.4.0-build.1", than: "0.3.0-build.99"))
        #expect(!SemVer.isNewer("0.2.0-build.2", than: "0.3.0-build.3"))
        #expect(!SemVer.isNewer("0.3.0-build.3", than: "0.3.0-build.3"))
    }

    @Test func garbageIsNeverNewer() {
        #expect(!SemVer.isNewer("latest", than: "0.3.0"))
        #expect(!SemVer.isNewer("1.2.3.4", than: "0.3.0"))
        #expect(!SemVer.isNewer("", than: "0.3.0"))
    }

    // MARK: Decoding

    @Test func decodesStableAndBeta() {
        let result = Self.feed("""
            {"version":"0.4.0-build.5","release_url":"https://kael.io.vn/r/1",
             "beta":{"version":"0.5.0-build.6","release_url":"https://kael.io.vn/r/2"}}
            """)
        guard case .success(let feed) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(feed.stable.version == "0.4.0-build.5")
        #expect(feed.beta?.version == "0.5.0-build.6")
    }

    @Test func statusCodesMapToFailures() {
        #expect(Self.feed("", status: 404) == .unavailable(.notFound))
        #expect(Self.feed("", status: 503) == .unavailable(.serverError))
        #expect(Self.feed("not json") == .unavailable(.malformed))
        #expect(Self.feed(#"{"version":""}"#) == .unavailable(.malformed))
    }

    @Test func deeplyNestedJSONIsRefusedBeforeParsing() {
        let nested = String(repeating: "[", count: 5000) + String(repeating: "]", count: 5000)
        #expect(!RemoteJSON.isAcceptable(Data(nested.utf8)))
        #expect(Self.feed(nested) == .unavailable(.malformed))
    }

    @Test func bracketsInsideStringsDoNotCount() {
        let json = #"{"version":"[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[\"{"}"#
        #expect(RemoteJSON.isAcceptable(Data(json.utf8), maxDepth: 2))
    }

    @Test func oversizedBodyIsRefused() {
        #expect(!RemoteJSON.isAcceptable(Data(count: RemoteJSON.maxBytes + 1)))
    }

    @Test func onlyHTTPSReleasePagesAreKept() {
        for unsafe in ["file:///Applications/Calculator.app", "http://kael.io.vn/r", "javascript:alert(1)",
                       "nexus://open", "https:///nohost"] {
            #expect(UpdateFeed.Wire.webURL(unsafe) == nil, "\(unsafe)")
        }
        #expect(UpdateFeed.Wire.webURL("https://kael.io.vn/r/1") != nil)
    }

    @Test func anUpdateWithAnUnsafeLinkIsNotOffered() {
        guard case .success(let feed) = Self.feed(#"{"version":"9.0.0","release_url":"file:///etc/hosts"}"#)
        else {
            Issue.record("expected success")
            return
        }
        #expect(UpdateSelection.pick(feed: feed, currentVersion: "0.3.0-build.3", channel: .stable) == nil)
    }

    @Test func bodyBudgetRefusesBeforeTaking() {
        var budget = BodyBudget(limit: 10)
        let first = budget.take(6)
        let second = budget.take(5)
        #expect(first)
        #expect(!second)
        #expect(budget.used == 6)
        #expect(budget.admits(announcedLength: -1))
        #expect(!budget.admits(announcedLength: 11))
    }

    // MARK: Selection

    private static let both = UpdateFeed(
        stable: UpdateFeedEntry(version: "0.4.0-build.5", releaseURL: https),
        beta: UpdateFeedEntry(version: "0.5.0-build.6", releaseURL: https)
    )

    @Test func stableChannelIgnoresBeta() {
        let pick = UpdateSelection.pick(feed: Self.both, currentVersion: "0.3.0-build.3", channel: .stable)
        #expect(pick?.version == "0.4.0-build.5")
    }

    @Test func betaChannelTakesTheNewerBeta() {
        let pick = UpdateSelection.pick(feed: Self.both, currentVersion: "0.3.0-build.3", channel: .beta)
        #expect(pick?.version == "0.5.0-build.6")
    }

    @Test func betaChannelStillGetsANewerStable() {
        let feed = UpdateFeed(
            stable: UpdateFeedEntry(version: "0.6.0-build.7", releaseURL: Self.https),
            beta: UpdateFeedEntry(version: "0.5.0-build.6", releaseURL: Self.https))
        #expect(UpdateSelection.pick(feed: feed, currentVersion: "0.3.0-build.3", channel: .beta)?.version
            == "0.6.0-build.7")
    }

    @Test func nothingNewerMeansNoOffer() {
        #expect(UpdateSelection.pick(feed: Self.both, currentVersion: "0.6.0-build.1", channel: .beta) == nil)
    }

    @Test func displayVersionReadsLikeAbout() {
        #expect(UpdateAvailable(version: "0.4.0-build.5", releaseURL: Self.https).displayVersion == "0.4.0 (5)")
        #expect(UpdateAvailable(version: "0.4.0", releaseURL: Self.https).displayVersion == "0.4.0")
    }

    // MARK: Checker

    @MainActor
    private static func checker(
        _ result: UpdateFeedResult, channel: UpdateChannel = .stable
    ) -> UpdateChecker {
        UpdateChecker(
            currentVersion: { "0.3.0-build.3" },
            channel: { channel },
            isAutomatic: { true },
            fetch: { result }
        )
    }

    @Test @MainActor func checkerOffersANewerVersion() async {
        let checker = Self.checker(.success(Self.both))
        #expect(checker.state == .idle)
        await checker.checkNow()
        #expect(checker.offeredUpdate?.version == "0.4.0-build.5")
        #expect(checker.failureText == nil)
    }

    @Test @MainActor func checkerSaysUpToDate() async {
        let feed = UpdateFeed(stable: UpdateFeedEntry(version: "0.2.0-build.2", releaseURL: Self.https), beta: nil)
        let checker = Self.checker(.success(feed))
        await checker.checkNow()
        #expect(checker.state == .upToDate)
        #expect(checker.offeredUpdate == nil)
    }

    @Test @MainActor func aFailedCheckNeverReadsAsUpToDate() async {
        let checker = Self.checker(.unavailable(.timeout))
        await checker.checkNow()
        #expect(checker.state == .unavailable(.timeout))
        #expect(checker.buttonLabel == String(localized: "Retry"))
        #expect(checker.failureText != nil)
    }

    @Test @MainActor func automaticChecksOffMakeNoRequest() async throws {
        let calls = Counter()
        let checker = UpdateChecker(
            currentVersion: { "0.3.0-build.3" },
            channel: { .stable },
            isAutomatic: { false },
            fetch: {
                await calls.increment()
                return .unavailable(.transport)
            }
        )
        checker.startAutomaticChecks()
        for _ in 0..<20 { await Task.yield() }
        checker.stop()
        #expect(await calls.value == 0)
        #expect(checker.state == .idle)
    }

    // MARK: Configuration

    @Test func updatesDefaultOnAndStable() {
        #expect(GeneralConfiguration().checkForUpdates)
        #expect(GeneralConfiguration().updateChannel == .stable)
    }

    @Test func olderConfigurationGetsTheDefaults() throws {
        let general = try JSONDecoder().decode(GeneralConfiguration.self, from: Data(#"{"showClock":false}"#.utf8))
        #expect(general.checkForUpdates)
        #expect(general.updateChannel == .stable)
        #expect(general.showClock == false)
    }

    @Test func unknownChannelResolvesToStableWithoutLosingTheSection() throws {
        let json = #"{"updateChannel":"earlyAccess","checkForUpdates":false,"showVolume":false}"#
        let general = try JSONDecoder().decode(GeneralConfiguration.self, from: Data(json.utf8))
        #expect(general.updateChannel == .stable)
        #expect(general.checkForUpdates == false)
        #expect(general.showVolume == false)
    }

    @Test func channelRoundTrips() throws {
        var general = GeneralConfiguration()
        general.updateChannel = .beta
        general.checkForUpdates = false
        let decoded = try JSONDecoder().decode(GeneralConfiguration.self, from: JSONEncoder().encode(general))
        #expect(decoded == general)
    }

    // MARK: Feed address

    @Test func feedIsHTTPSOnTheBugAppsSite() {
        #expect(UpdateFeedFetcher.feedURL.absoluteString == "https://kael.io.vn/projects/nexus/latest.json")
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
