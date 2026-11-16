import AppKit
import Foundation

/// Where a player is in what it is playing (M16).
public struct MediaPosition: Sendable, Equatable {
    /// Seconds from the start.
    public var position: Double
    /// Seconds in total. Zero when the player will not say, which is the same as "no timeline".
    public var duration: Double

    public init(position: Double, duration: Double) {
        self.position = position
        self.duration = duration
    }

    public var hasTimeline: Bool { duration > 1 && position >= 0 }

    /// 0…1, for drawing. Clamped, because a player that reports a position past its own duration is
    /// not a reason to draw outside the track.
    public var fraction: Double {
        guard hasTimeline else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// `1:58`, or `1:02:07` past an hour. What a clock next to a scrubber has to be.
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let (hours, minutes, remainder) = (total / 3_600, (total % 3_600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}

/// What a player is doing: where it is, and whether it is actually playing.
public struct MediaPlayback: Sendable, Equatable {
    public var position: MediaPosition
    public var isPlaying: Bool

    public init(position: MediaPosition, isPlaying: Bool) {
        self.position = position
        self.isPlaying = isPlaying
    }
}

/// The transport commands a player understands. Sent as a script where the player has a scripting
/// dictionary, and as a media key where it does not (D83).
public enum MediaTransport: Sendable, CaseIterable {
    case playPause
    case next
    case previous
}

public protocol MediaPositionControlling: Sendable {
    func playback(of bundleIdentifier: String) async -> MediaPlayback?
    func seek(to seconds: Double, in bundleIdentifier: String) async
    /// `false` when the player would not take it, so the caller can fall back to a media key.
    func command(_ transport: MediaTransport, in bundleIdentifier: String) async -> Bool
}

/// Position and seeking, over the scripting interfaces the players already publish.
///
/// This is the one thing `MediaRemote` would have answered for everybody (D75) and nothing public
/// will: there is no API that reports how far into a video a browser tab is. What there is, is
/// AppleScript for the applications that ship a scripting dictionary — Music, Spotify, VLC — and
/// nothing at all for the rest, which get the row without a scrubber rather than a fake one.
public actor AppleScriptMediaControl: MediaPositionControlling {
    /// Per player: how to read a position, how to write one, and whether the duration it reports is
    /// in milliseconds (Spotify's is).
    struct Dialect: Sendable {
        /// Returns `{position, duration, isPlaying}`.
        let read: String
        let seek: @Sendable (Double) -> String
        let transport: [MediaTransport: String]
        let durationIsMilliseconds: Bool
    }

    private static func appleTransport(_ id: String) -> [MediaTransport: String] {
        [
            .playPause: #"tell application id "\#(id)" to playpause"#,
            .next: #"tell application id "\#(id)" to next track"#,
            .previous: #"tell application id "\#(id)" to previous track"#,
        ]
    }

    static let dialects: [String: Dialect] = [
        "com.apple.Music": Dialect(
            read: #"tell application id "com.apple.Music" to return {player position, duration of current track, player state is playing}"#,
            seek: { #"tell application id "com.apple.Music" to set player position to \#($0)"# },
            transport: appleTransport("com.apple.Music"),
            durationIsMilliseconds: false
        ),
        "com.apple.iTunes": Dialect(
            read: #"tell application id "com.apple.iTunes" to return {player position, duration of current track, player state is playing}"#,
            seek: { #"tell application id "com.apple.iTunes" to set player position to \#($0)"# },
            transport: appleTransport("com.apple.iTunes"),
            durationIsMilliseconds: false
        ),
        "com.spotify.client": Dialect(
            read: #"tell application id "com.spotify.client" to return {player position, duration of current track, player state is playing}"#,
            seek: { #"tell application id "com.spotify.client" to set player position to \#($0)"# },
            transport: appleTransport("com.spotify.client"),
            durationIsMilliseconds: true
        ),
        "org.videolan.vlc": Dialect(
            read: #"tell application id "org.videolan.vlc" to return {current time, duration of current item, playing}"#,
            seek: { #"tell application id "org.videolan.vlc" to set current time to \#(Int($0))"# },
            // VLC's `play` toggles, and its next/previous move through the playlist.
            transport: [
                .playPause: #"tell application id "org.videolan.vlc" to play"#,
                .next: #"tell application id "org.videolan.vlc" to next"#,
                .previous: #"tell application id "org.videolan.vlc" to previous"#,
            ],
            durationIsMilliseconds: false
        ),
    ]

    /// Players that answered "no". Asking again would mean another Automation prompt per second.
    private var refused: Set<String> = []
    /// Consecutive timeouts per player. A slow answer is not a refusal, but a player that never
    /// answers is not worth a stalled script a second.
    private var timeouts: [String: Int] = [:]
    /// Players that have answered at least once. Until then a timeout is probably the first-run
    /// Automation consent prompt waiting for the owner, and must not count against the player.
    private var answered: Set<String> = []
    private let runner: any ScriptRunning

    public init(runner: any ScriptRunning = AppleScriptRunner()) {
        self.runner = runner
    }

    public static func canReportPosition(_ bundleIdentifier: String) -> Bool {
        dialects[bundleIdentifier] != nil
    }

    public func playback(of bundleIdentifier: String) async -> MediaPlayback? {
        guard let dialect = Self.dialects[bundleIdentifier], !refused.contains(bundleIdentifier)
        else { return nil }

        switch await runner.run(dialect.read) {
        case .values(let values) where values.count == 3:
            noteSuccess(bundleIdentifier)
            let duration = dialect.durationIsMilliseconds ? values[1] / 1_000 : values[1]
            return MediaPlayback(
                position: MediaPosition(position: values[0], duration: duration),
                isPlaying: values[2] != 0
            )
        case .timedOut:
            noteTimeout(bundleIdentifier)
            return nil
        case .values(let values):
            Log.system.notice("Media script answered \(values.count, privacy: .public) items, expected 3")
            refuse(bundleIdentifier)
            return nil
        case .empty, .failed:
            refuse(bundleIdentifier)
            return nil
        }
    }

    public func command(_ transport: MediaTransport, in bundleIdentifier: String) async -> Bool {
        guard let source = Self.dialects[bundleIdentifier]?.transport[transport],
              !refused.contains(bundleIdentifier)
        else { return false }
        return await succeeded(runner.run(source), for: bundleIdentifier)
    }

    public func seek(to seconds: Double, in bundleIdentifier: String) async {
        guard let dialect = Self.dialects[bundleIdentifier], !refused.contains(bundleIdentifier)
        else { return }
        switch await runner.run(dialect.seek(max(0, seconds))) {
        case .values: noteSuccess(bundleIdentifier)
        case .empty: timeouts[bundleIdentifier] = 0
        case .timedOut: noteTimeout(bundleIdentifier)
        case .failed: refuse(bundleIdentifier)
        }
    }

    /// A timeout means the Apple Event was delivered and the player answered late: `true`, so the
    /// caller does not also send a media key and toggle twice. Only `.failed` is "would not take it".
    private func succeeded(_ outcome: ScriptOutcome, for bundleIdentifier: String) -> Bool {
        switch outcome {
        case .values:
            noteSuccess(bundleIdentifier)
            return true
        case .empty:
            timeouts[bundleIdentifier] = 0
            return true
        case .timedOut:
            noteTimeout(bundleIdentifier)
            return true
        case .failed:
            return false
        }
    }

    private func noteSuccess(_ bundleIdentifier: String) {
        timeouts[bundleIdentifier] = 0
        answered.insert(bundleIdentifier)
    }

    private func noteTimeout(_ bundleIdentifier: String) {
        guard answered.contains(bundleIdentifier) else { return }
        let count = (timeouts[bundleIdentifier] ?? 0) + 1
        timeouts[bundleIdentifier] = count
        if count >= 3 { refuse(bundleIdentifier) }
    }

    private func refuse(_ bundleIdentifier: String) {
        guard refused.insert(bundleIdentifier).inserted else { return }
        Log.system.notice(
            "\(bundleIdentifier, privacy: .public) will not report its position; no timeline for it"
        )
    }
}

/// For tests and for players that answer nothing.
public struct NoMediaPosition: MediaPositionControlling {
    public init() {}
    public func playback(of bundleIdentifier: String) async -> MediaPlayback? { nil }
    public func seek(to seconds: Double, in bundleIdentifier: String) async {}
    public func command(_ transport: MediaTransport, in bundleIdentifier: String) async -> Bool { false }
}
