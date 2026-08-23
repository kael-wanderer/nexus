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

public protocol MediaPositionControlling: Sendable {
    func position(of bundleIdentifier: String) async -> MediaPosition?
    func seek(to seconds: Double, in bundleIdentifier: String) async
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
        let read: String
        let seek: @Sendable (Double) -> String
        let durationIsMilliseconds: Bool
    }

    static let dialects: [String: Dialect] = [
        "com.apple.Music": Dialect(
            read: #"tell application id "com.apple.Music" to return {player position, duration of current track}"#,
            seek: { #"tell application id "com.apple.Music" to set player position to \#($0)"# },
            durationIsMilliseconds: false
        ),
        "com.apple.iTunes": Dialect(
            read: #"tell application id "com.apple.iTunes" to return {player position, duration of current track}"#,
            seek: { #"tell application id "com.apple.iTunes" to set player position to \#($0)"# },
            durationIsMilliseconds: false
        ),
        "com.spotify.client": Dialect(
            read: #"tell application id "com.spotify.client" to return {player position, duration of current track}"#,
            seek: { #"tell application id "com.spotify.client" to set player position to \#($0)"# },
            durationIsMilliseconds: true
        ),
        "org.videolan.vlc": Dialect(
            read: #"tell application id "org.videolan.vlc" to return {current time, duration of current item}"#,
            seek: { #"tell application id "org.videolan.vlc" to set current time to \#(Int($0))"# },
            durationIsMilliseconds: false
        ),
    ]

    /// Players that answered "no". Asking again would mean another Automation prompt per second.
    private var refused: Set<String> = []

    public init() {}

    public static func canReportPosition(_ bundleIdentifier: String) -> Bool {
        dialects[bundleIdentifier] != nil
    }

    public func position(of bundleIdentifier: String) async -> MediaPosition? {
        guard let dialect = Self.dialects[bundleIdentifier], !refused.contains(bundleIdentifier)
        else { return nil }

        guard let pair = await Self.runForPair(dialect.read) else {
            refuse(bundleIdentifier)
            return nil
        }
        let duration = dialect.durationIsMilliseconds ? pair.1 / 1_000 : pair.1
        return MediaPosition(position: pair.0, duration: duration)
    }

    public func seek(to seconds: Double, in bundleIdentifier: String) async {
        guard let dialect = Self.dialects[bundleIdentifier], !refused.contains(bundleIdentifier)
        else { return }
        if await Self.run(dialect.seek(max(0, seconds))) == false { refuse(bundleIdentifier) }
    }

    private func refuse(_ bundleIdentifier: String) {
        guard refused.insert(bundleIdentifier).inserted else { return }
        Log.system.notice(
            "\(bundleIdentifier, privacy: .public) will not report its position; no timeline for it"
        )
    }

    /// `nil` on any failure at all — a refused Automation prompt, a player that quit mid-script, a
    /// dictionary that changed. The caller's answer to all three is the same: no timeline.
    ///
    /// On the main actor because `NSAppleScript` is not thread-safe, and at `.notice` because a
    /// failure here is invisible otherwise: a silently missing timeline is exactly the class of bug
    /// that took three rebuilds to find at Milestone 10 (D66).
    @MainActor
    static func runForPair(_ source: String) -> (Double, Double)? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            Log.system.notice("Media script failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        guard result.numberOfItems >= 2,
              let position = result.atIndex(1)?.doubleValue,
              let duration = result.atIndex(2)?.doubleValue
        else {
            Log.system.notice(
                "Media script answered \(result.numberOfItems, privacy: .public) items, expected 2"
            )
            return nil
        }
        return (position, duration)
    }

    @MainActor
    @discardableResult
    static func run(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        if let error {
            Log.system.notice("Media script failed: \(String(describing: error), privacy: .public)")
            return false
        }
        return true
    }
}

/// For tests and for players that answer nothing.
public struct NoMediaPosition: MediaPositionControlling {
    public init() {}
    public func position(of bundleIdentifier: String) async -> MediaPosition? { nil }
    public func seek(to seconds: Double, in bundleIdentifier: String) async {}
}
