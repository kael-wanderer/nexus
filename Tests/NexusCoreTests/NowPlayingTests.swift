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
