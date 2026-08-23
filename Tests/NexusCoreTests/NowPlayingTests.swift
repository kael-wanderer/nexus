import Foundation
import Testing

@testable import NexusCore

@Suite("Now playing metadata")
struct NowPlayingSourceTests {
    @Test("Music's payload becomes a track")
    func music() {
        let playing = NowPlayingSource.parse(
            [
                "Name": "Tunnel Vision",
                "Artist": "Aurora B.Polaris",
                "Album": "Tunnel Vision",
                "Player State": "Playing",
            ],
            bundleIdentifier: "com.apple.Music"
        )
        #expect(playing.title == "Tunnel Vision")
        #expect(playing.artist == "Aurora B.Polaris")
        #expect(playing.isPlaying)
        #expect(playing.playerBundleIdentifier == "com.apple.Music")
        #expect(playing.hasMetadata)
    }

    @Test("Spotify's payload uses the same keys, which is why one parser covers both")
    func spotify() {
        let playing = NowPlayingSource.parse(
            ["Name": "Weightless", "Artist": "Marconi Union", "Player State": "Paused"],
            bundleIdentifier: "com.spotify.client"
        )
        #expect(playing.title == "Weightless")
        #expect(playing.isPlaying == false)
        // Paused with a track is still worth a row: the controls work and the title is real.
        #expect(NowPlayingSource.isIdle(playing) == false)
    }

    @Test("A stopped player with no track is idle")
    func stopped() {
        let playing = NowPlayingSource.parse(
            ["Player State": "Stopped"],
            bundleIdentifier: "com.apple.Music"
        )
        #expect(NowPlayingSource.isIdle(playing))
        #expect(playing.hasMetadata == false)
    }

    @Test("An empty title is no title, rather than an empty row")
    func blankTitle() {
        let playing = NowPlayingSource.parse(
            ["Name": "   ", "Player State": "Playing"],
            bundleIdentifier: "com.spotify.client"
        )
        #expect(playing.title == nil)
        #expect(playing.isPlaying)
    }
}

@MainActor
@Suite("Now playing service")
struct NowPlayingServiceTests {
    private func makeService() -> (NowPlayingService, Box) {
        let service = NowPlayingService()
        let box = Box()
        service.send = { key in box.keys.append(key) }
        service.onChange = { playing, active in box.changes.append((playing, active)) }
        return (service, box)
    }

    final class Box {
        var keys: [MediaKey] = []
        var changes: [(NowPlaying, Bool)] = []
    }

    @Test("A track arriving makes the service active and publishes once")
    func trackArrives() {
        let (service, box) = makeService()

        service.received(
            NowPlayingSource.parse(
                ["Name": "Tunnel Vision", "Player State": "Playing"],
                bundleIdentifier: "com.spotify.client"
            )
        )

        #expect(service.current.title == "Tunnel Vision")
        #expect(service.isActive)
        #expect(box.changes.count == 1)

        // The same payload again changes nothing, so the bar does not re-lay itself for nothing.
        service.received(
            NowPlayingSource.parse(
                ["Name": "Tunnel Vision", "Player State": "Playing"],
                bundleIdentifier: "com.spotify.client"
            )
        )
        #expect(box.changes.count == 1)
    }

    @Test("The player that stopped is the only one that can clear the row")
    func stopClearsOnlyItsOwn() {
        let (service, _) = makeService()
        service.received(
            NowPlayingSource.parse(["Name": "Weightless", "Player State": "Playing"], bundleIdentifier: "com.spotify.client")
        )

        // Music says it stopped: Spotify's track stays.
        service.received(
            NowPlayingSource.parse(["Player State": "Stopped"], bundleIdentifier: "com.apple.Music")
        )
        #expect(service.current.title == "Weightless")

        // Spotify says it stopped: the row clears.
        service.received(
            NowPlayingSource.parse(["Player State": "Stopped"], bundleIdentifier: "com.spotify.client")
        )
        #expect(service.current.title == nil)
        #expect(service.isActive == false)
    }

    /// The device-level question was tried first and is useless: a browser holds the output device
    /// open for hours without making a sound. Per process it is exact, and it names the player.
    @Test("An application making sound is enough for a row, and it names the player")
    func audioPlayers() {
        let (service, box) = makeService()

        service.setAudioPlayers(["com.brave.Browser"])
        #expect(service.isActive)
        #expect(service.audioIsActive)
        #expect(service.current.hasMetadata == false)
        #expect(box.changes.count == 1)

        service.setAudioPlayers([])
        #expect(service.isActive == false)
        #expect(box.changes.count == 2)
    }

    @Test("Transport controls post media keys and nothing else")
    func controls() {
        let (service, box) = makeService()
        service.toggle()
        service.next()
        service.previous()
        #expect(box.keys == [.play, .next, .previous])
    }

    /// The key in the high half, the up/down state in the low half — what a keyboard's own
    /// transport keys send, and the reason this works for a browser tab that no API will name.
    @Test("The event payload matches the NX_KEYTYPE layout")
    func keyPayload() {
        #expect(MediaKeys.data1(.play, isDown: true) == (16 << 16) | (0xA << 8))
        #expect(MediaKeys.data1(.play, isDown: false) == (16 << 16) | (0xB << 8))
        #expect(MediaKeys.data1(.next, isDown: true) == (17 << 16) | (0xA << 8))
        #expect(MediaKeys.data1(.previous, isDown: true) == (18 << 16) | (0xA << 8))
    }
}

@Suite("Titles from window titles")
struct MediaTitleTests {
    /// The case that started this: VLC's window title is the file, and the file is the movie.
    @Test("A file name loses its extension")
    func fileName() {
        #expect(MediaTitle.clean("Loki S01 - Newmoon21.mkv", applicationName: "VLC") == "Loki S01 - Newmoon21")
        #expect(MediaTitle.clean("Weightless.mp3", applicationName: "VLC") == "Weightless")
    }

    @Test("A tab title loses the site and the browser, and keeps the hyphens that are the title's")
    func tabTitle() {
        #expect(
            MediaTitle.clean("Aurora B.Polaris - Tunnel Vision - YouTube", applicationName: "Brave Browser")
                == "Aurora B.Polaris - Tunnel Vision"
        )
        #expect(
            MediaTitle.clean("Some Show S02E04 — Netflix — Google Chrome", applicationName: "Google Chrome")
                == "Some Show S02E04"
        )
    }

    @Test("A window that says nothing but the application's own name is not a title")
    func noTitle() {
        // Chrome's real window title: the site, its own note about the tab, its name, and the
        // profile. Everything from the site onwards is furniture (D89).
        #expect(
            MediaTitle.clean(
                "Đánh giá Nintendo Switch 2 sau hơn một năm sử dụng - YouTube - Audio playing - Google Chrome - Cong",
                applicationName: "Google Chrome"
            ) == "Đánh giá Nintendo Switch 2 sau hơn một năm sử dụng"
        )
        // A profile name alone, with no site in the way, still does not survive the browser's note.
        #expect(
            MediaTitle.clean(
                "Some Tab - Audio playing - Google Chrome - Work",
                applicationName: "Google Chrome"
            ) == "Some Tab"
        )
        #expect(MediaTitle.clean("VLC media player", applicationName: "VLC media player") == nil)
        #expect(MediaTitle.clean("   ", applicationName: "VLC") == nil)
    }

    @Test("A title that happens to contain a dash keeps it")
    func keepsInnerDashes() {
        #expect(
            MediaTitle.clean("Post-Rock Mix - Vol 3", applicationName: "Music") == "Post-Rock Mix - Vol 3"
        )
    }
}

@MainActor
@Suite("Now playing display")
struct NowPlayingDisplayTests {
    @Test("Published metadata wins; a window title fills in when there is none")
    func displayPrefersMetadata() async {
        let service = NowPlayingService()
        service.windowTitle = { _ in "Loki S01 - Newmoon21.mkv" }

        service.setAudioPlayers(["org.videolan.vlc"])
        await until { service.windowDerivedTitle != nil }
        #expect(service.display.title == "Loki S01 - Newmoon21")

        // Spotify starts publishing: its metadata replaces the guess.
        service.received(
            NowPlayingSource.parse(
                ["Name": "Weightless", "Artist": "Marconi Union", "Player State": "Playing"],
                bundleIdentifier: "com.spotify.client"
            )
        )
        #expect(service.display.title == "Weightless")
        #expect(service.display.artist == "Marconi Union")
    }

    @Test("Nothing playing clears the derived title too")
    func clearsOnIdle() async {
        let service = NowPlayingService()
        service.windowTitle = { _ in "Something.mp4" }
        service.setAudioPlayers(["org.videolan.vlc"])
        await until { service.windowDerivedTitle != nil }

        service.setAudioPlayers([])
        #expect(service.windowDerivedTitle == nil)
        #expect(service.display.title == nil)
    }
}

/// Polls until `condition` holds, up to two seconds.
@MainActor
private func until(_ condition: () -> Bool) async {
    for _ in 0..<200 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}


@Suite("Media position")
struct MediaPositionTests {
    @Test("A duration under a second is no timeline")
    func noTimeline() {
        #expect(MediaPosition(position: 0, duration: 0).hasTimeline == false)
        #expect(MediaPosition(position: 5, duration: 240).hasTimeline)
    }

    @Test("The fraction is clamped, because a player past its own duration is not a drawing bug")
    func fraction() {
        #expect(MediaPosition(position: 120, duration: 240).fraction == 0.5)
        #expect(MediaPosition(position: 300, duration: 240).fraction == 1)
        #expect(MediaPosition(position: -4, duration: 240).fraction == 0)
    }

    @Test("The clock grows an hours field only when there is one")
    func clock() {
        #expect(MediaPosition.clock(118) == "1:58")
        #expect(MediaPosition.clock(3_727) == "1:02:07")
        #expect(MediaPosition.clock(0) == "0:00")
        #expect(MediaPosition.clock(-1) == "0:00")
        #expect(MediaPosition.clock(.nan) == "0:00")
    }

    @Test("Only the players with a scripting dictionary can report a position")
    func dialects() {
        #expect(AppleScriptMediaControl.canReportPosition("com.spotify.client"))
        #expect(AppleScriptMediaControl.canReportPosition("org.videolan.vlc"))
        #expect(AppleScriptMediaControl.canReportPosition("com.apple.Music"))
        // A browser tab: nothing public will say where it is.
        #expect(AppleScriptMediaControl.canReportPosition("com.brave.Browser") == false)
    }

    /// Spotify reports milliseconds where everyone else reports seconds, which is exactly the kind
    /// of thing that silently makes a four-minute song look like a four-thousand-second one.
    @Test("Spotify's duration is milliseconds and is converted")
    func spotifyMilliseconds() {
        #expect(AppleScriptMediaControl.dialects["com.spotify.client"]?.durationIsMilliseconds == true)
        // And every dialect can be told to play, skip and go back.
        for (identifier, dialect) in AppleScriptMediaControl.dialects {
            #expect(dialect.transport.count == MediaTransport.allCases.count, "\(identifier)")
        }
        #expect(AppleScriptMediaControl.dialects["com.apple.Music"]?.durationIsMilliseconds == false)
        #expect(AppleScriptMediaControl.dialects["org.videolan.vlc"]?.durationIsMilliseconds == false)
    }
}

/// A player that answers, for the tests that need one.
actor FakeMediaControl: MediaPositionControlling {
    private var reading: MediaPlayback?
    private(set) var seeks: [Double] = []
    private(set) var commands: [MediaTransport] = []
    private let acceptsCommands: Bool

    init(_ position: MediaPosition?, isPlaying: Bool = true, acceptsCommands: Bool = true) {
        reading = position.map { MediaPlayback(position: $0, isPlaying: isPlaying) }
        self.acceptsCommands = acceptsCommands
    }

    func playback(of bundleIdentifier: String) async -> MediaPlayback? { reading }

    func seek(to seconds: Double, in bundleIdentifier: String) async {
        seeks.append(seconds)
        reading?.position.position = seconds
    }

    func command(_ transport: MediaTransport, in bundleIdentifier: String) async -> Bool {
        commands.append(transport)
        if transport == .playPause { reading?.isPlaying.toggle() }
        return acceptsCommands
    }
}

@MainActor
@Suite("Position polling")
struct PositionPollingTests {
    @Test("Nothing is read until the player is on screen, and reading stops when it goes away")
    func gatedOnVisibility() async {
        let control = FakeMediaControl(MediaPosition(position: 30, duration: 240))
        let service = NowPlayingService(control: control)
        service.setAudioPlayers(["com.spotify.client"])

        #expect(service.position == nil)

        service.setPlayerVisible(true)
        await untilPolled { service.position != nil }
        #expect(service.position?.duration == 240)

        service.setPlayerVisible(false)
        // Nothing further arrives; the reading it had is left alone rather than blanked.
        #expect(service.position?.duration == 240)
    }

    @Test("A seek moves the thumb at once and tells the player once")
    func seek() async {
        let control = FakeMediaControl(MediaPosition(position: 30, duration: 240))
        let service = NowPlayingService(control: control)
        service.setAudioPlayers(["com.spotify.client"])
        service.setPlayerVisible(true)
        await untilPolled { service.position != nil }

        service.seek(to: 120)
        #expect(service.position?.position == 120)      // optimistic, no waiting for the next read
        await untilPolled { await control.seeks.isEmpty == false }
        #expect(await control.seeks == [120])
    }

    @Test("A player that answers nothing gets no timeline, and no repeated asking")
    func silentPlayer() async {
        let service = NowPlayingService(control: FakeMediaControl(nil))
        service.setAudioPlayers(["com.brave.Browser"])
        service.setPlayerVisible(true)

        try? await Task.sleep(for: .milliseconds(80))
        #expect(service.position == nil)
    }
}

@MainActor
private func untilPolled(_ condition: () async -> Bool) async {
    for _ in 0..<200 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
@Suite("Pausing keeps the player")
struct PausedPlayerTests {
    /// The bug: pausing stopped the audio, the audio was the only evidence of a player, and the row
    /// vanished — leaving nothing to press play on.
    @Test("A scriptable player that pauses keeps its row")
    func pauseKeepsRow() async {
        let control = FakeMediaControl(MediaPosition(position: 30, duration: 240))
        let service = NowPlayingService(control: control)
        service.setAudioPlayers(["org.videolan.vlc"])
        service.setPlayerVisible(true)
        await untilPolled { service.position != nil }

        // Pause: no more audio anywhere, but VLC still has the film loaded.
        service.setAudioPlayers([])
        #expect(service.isActive)
        #expect(service.display.playerBundleIdentifier == "org.videolan.vlc")
    }

    @Test("A player that stops answering at all loses its row")
    func closedPlayerLosesRow() async {
        let control = FakeMediaControl(nil)
        let service = NowPlayingService(control: control)
        service.setAudioPlayers(["org.videolan.vlc"])
        service.setPlayerVisible(true)
        service.setAudioPlayers([])

        await untilPolled { service.isActive == false }
        #expect(service.isActive == false)
    }

    @Test("A browser tab that stops making sound loses its row, since nothing can be asked")
    func browserLosesRow() {
        let service = NowPlayingService(control: FakeMediaControl(nil))
        service.setAudioPlayers(["com.brave.Browser"])
        #expect(service.isActive)

        service.setAudioPlayers([])
        #expect(service.isActive == false)
    }

    @Test("Transport goes through the script for a scriptable player, and the state follows")
    func scriptedTransport() async {
        let control = FakeMediaControl(MediaPosition(position: 30, duration: 240))
        let service = NowPlayingService(control: control)
        var keys: [MediaKey] = []
        service.send = { keys.append($0) }
        service.setAudioPlayers(["org.videolan.vlc"])
        service.setPlayerVisible(true)
        await untilPolled { service.position != nil }

        service.toggle()
        await untilPolled { await control.commands.isEmpty == false }
        #expect(await control.commands == [.playPause])
        #expect(keys.isEmpty)                         // no media key needed
        await untilPolled { service.scriptedIsPlaying == false }
        #expect(service.display.isPlaying == false)   // the button becomes a play button
    }

    @Test("A player with no dictionary gets a media key instead")
    func keyFallback() {
        let service = NowPlayingService(control: FakeMediaControl(nil))
        var keys: [MediaKey] = []
        service.send = { keys.append($0) }
        service.setAudioPlayers(["com.brave.Browser"])

        service.toggle()
        service.next()
        #expect(keys == [.play, .next])
    }
}


@Suite("Audio owner resolution")
struct AudioOwnerTests {
    @Test("This process resolves to its own bundle identifier, directly")
    func ownProcess() {
        let own = ProcessInfo.processInfo.processIdentifier
        // The test runner is not an application bundle, so the path route is what answers — and
        // whatever answers, it must not be nil for a process that is plainly running.
        let resolved = AudioOutputMonitor.owningBundleIdentifier(of: own)
            ?? AudioOutputMonitor.executablePath(of: own)
        #expect(resolved != nil)
    }

    @Test("A helper inside an application bundle resolves to the application, not the helper")
    func helperInsideBundle() {
        // Chrome's layout, which is the case that had no row at all: two nested .app bundles, and
        // the outer one is the answer.
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/151.0.7922.173/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        var url = URL(fileURLWithPath: path)
        var bundles: [URL] = []
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" { bundles.append(url) }
            url = url.deletingLastPathComponent()
        }
        #expect(bundles.count == 2)
        #expect(bundles.last?.lastPathComponent == "Google Chrome.app")
        #expect(bundles.first?.lastPathComponent == "Google Chrome Helper.app")
    }

    @Test("A pid that cannot exist resolves to nothing rather than crashing")
    func missingProcess() {
        #expect(AudioOutputMonitor.owningBundleIdentifier(of: pid_t(Int32.max)) == nil)
        #expect(AudioOutputMonitor.parentProcess(of: pid_t(Int32.max)) == nil)
    }

    @Test("launchd's children report no owner rather than launchd")
    func launchdParent() {
        // pid 1 is launchd; its own parent is 0, which owns nothing in particular.
        #expect(AudioOutputMonitor.parentProcess(of: 1) == nil)
    }
}

@MainActor
@Suite("A browser's play state")
struct BrowserPlayStateTests {
    @Test("The marker is read case-insensitively, and muted still counts as playing")
    func markers() {
        #expect(MediaTitle.saysAudioIsPlaying("Video - YouTube - Audio playing - Google Chrome"))
        #expect(MediaTitle.saysAudioIsPlaying("Video - YouTube - audio muted - Google Chrome"))
        #expect(MediaTitle.saysAudioIsPlaying("Video - YouTube - Google Chrome") == false)
    }

    /// CoreAudio keeps reporting Chrome's renderer as sending output while the video sits paused —
    /// measured, not assumed — so the row used to show a pause button on a paused video. Chrome's
    /// window title is the only public thing that changes (D92).
    @Test("Losing the marker pauses the row, even while the audio process still says it is playing")
    func pausedBrowser() async {
        let service = NowPlayingService()
        var title = "A Video - YouTube - Audio playing - Google Chrome - Work"
        service.windowTitle = { _ in title }

        service.setAudioPlayers(["com.google.Chrome"])
        await until { service.windowDerivedTitle != nil }
        #expect(service.display.title == "A Video")
        #expect(service.display.isPlaying)

        // Paused: the marker goes, the audio process does not.
        title = "A Video - YouTube - Google Chrome - Work"
        service.refreshWindowTitle()
        await until { service.windowSaysPlaying == false }
        #expect(service.display.isPlaying == false)

        // Playing again.
        title = "A Video - YouTube - Audio playing - Google Chrome - Work"
        service.refreshWindowTitle()
        await until { service.windowSaysPlaying == true }
        #expect(service.display.isPlaying)
    }

    @Test("An application that never publishes a marker is still judged by its audio")
    func nonBrowser() async {
        let service = NowPlayingService()
        service.windowTitle = { _ in "Loki S01 - Newmoon21.mkv" }

        service.setAudioPlayers(["org.videolan.vlc"])
        await until { service.windowDerivedTitle != nil }
        #expect(service.windowSaysPlaying == nil)
        #expect(service.display.isPlaying)
    }
}
