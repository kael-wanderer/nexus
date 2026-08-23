import AppKit
import CoreAudio
import Foundation

/// What is playing, as far as macOS will say (M15).
public struct NowPlaying: Sendable, Equatable {
    public var title: String?
    public var artist: String?
    /// The application the metadata came from, so the row can draw its icon.
    public var playerBundleIdentifier: String?
    public var isPlaying: Bool

    public init(
        title: String? = nil,
        artist: String? = nil,
        playerBundleIdentifier: String? = nil,
        isPlaying: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.playerBundleIdentifier = playerBundleIdentifier
        self.isPlaying = isPlaying
    }

    /// A row with no title still earns its place: the controls work whoever is playing. What it
    /// must not do is invent a title.
    public var hasMetadata: Bool { title?.isEmpty == false }
}

/// The transport keys a keyboard has. Posting one reaches whichever application currently owns
/// media playback — including a browser tab, which no API will name for us.
public enum MediaKey: Int32, Sendable, CaseIterable {
    case play = 16          // NX_KEYTYPE_PLAY
    case next = 17          // NX_KEYTYPE_NEXT
    case previous = 18      // NX_KEYTYPE_PREVIOUS
}

/// Which players tell us what they are playing, and how.
///
/// `MediaRemote.framework` is what Control Center uses and would answer for every player at once.
/// It is private, and since macOS 15.4 it refuses callers without an Apple-internal entitlement —
/// building on it means shipping a feature that breaks on somebody's next software update. What is
/// left is public and pushed: Music and Spotify each post a distributed notification on every track
/// and state change (D75).
public enum NowPlayingSource: Sendable {
    public static let notifications: [(name: String, bundleIdentifier: String)] = [
        ("com.apple.Music.playerInfo", "com.apple.Music"),
        ("com.apple.iTunes.playerInfo", "com.apple.iTunes"),
        ("com.spotify.client.PlaybackStateChanged", "com.spotify.client"),
    ]

    /// Both players use the same keys, which is the only reason one parser covers them.
    public static func parse(_ userInfo: [AnyHashable: Any], bundleIdentifier: String) -> NowPlaying {
        let state = userInfo["Player State"] as? String
        let title = (userInfo["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = (userInfo["Artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NowPlaying(
            title: title?.isEmpty == false ? title : nil,
            artist: artist?.isEmpty == false ? artist : nil,
            playerBundleIdentifier: bundleIdentifier,
            isPlaying: state == "Playing"
        )
    }

    /// Whether a payload means "there is nothing to show" — stopped, or playing nothing.
    public static func isIdle(_ playing: NowPlaying) -> Bool {
        !playing.isPlaying && playing.title == nil
    }
}

/// Tracks what is playing and offers the transport controls.
///
/// Push only, twice over: the metadata arrives as distributed notifications, and "somebody is
/// playing audio" arrives as a CoreAudio property listener. Nothing here polls (§65).
@MainActor
@Observable
public final class NowPlayingService {
    public private(set) var current = NowPlaying()

    /// Applications actually sending audio out right now, by bundle identifier. It is how a browser
    /// tab gets controls and an icon: no public API names the *track* it is playing, but CoreAudio
    /// will say which process is making the sound.
    public private(set) var audioPlayers: [String] = []

    /// Injected so tests do not move the machine's actual playback.
    @ObservationIgnored public var send: (MediaKey) -> Void = MediaKeys.send
    /// Called whenever what is playing changes, or whether anything is. Push, because `@Observable`
    /// does not carry across types and a timer to notice a track change would be a timer (§65).
    @ObservationIgnored public var onChange: ((NowPlaying, Bool) -> Void)?

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var audioMonitor: AudioOutputMonitor?
    @ObservationIgnored private let center: DistributedNotificationCenter

    public init(center: DistributedNotificationCenter = .default()) {
        self.center = center
    }

    /// A row worth drawing: either a player told us something, or something is making sound and the
    /// controls will reach whoever owns it.
    public var isActive: Bool {
        current.isPlaying || current.hasMetadata || !audioPlayers.isEmpty
    }

    /// What the row draws when no player published a track: the application making the sound.
    public var audioIsActive: Bool { !audioPlayers.isEmpty }

    public func start() {
        for source in NowPlayingSource.notifications {
            let observer = center.addObserver(
                forName: Notification.Name(source.name),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                // Parsed here, off the main actor: a `Notification` is not `Sendable`, and what the
                // row needs from it is.
                let playing = NowPlayingSource.parse(
                    notification.userInfo ?? [:],
                    bundleIdentifier: source.bundleIdentifier
                )
                MainActor.assumeIsolated { self?.received(playing) }
            }
            observers.append(observer)
        }

        let monitor = AudioOutputMonitor { [weak self] players in
            MainActor.assumeIsolated { self?.setAudioPlayers(players) }
        }
        audioMonitor = monitor
        setAudioPlayers(monitor.start())
        Log.system.notice("Now playing: observing \(self.observers.count, privacy: .public) players")
    }

    public func stop() {
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
        audioMonitor?.stop()
        audioMonitor = nil
    }

    public func received(_ playing: NowPlaying) {
        // A player that stopped clears the row rather than leaving the last track on it — but only
        // if that player is the one the row is showing. Spotify pausing must not wipe Music.
        if NowPlayingSource.isIdle(playing) {
            if current.playerBundleIdentifier == playing.playerBundleIdentifier {
                set(NowPlaying())
            }
            return
        }
        set(playing)
    }

    private func set(_ playing: NowPlaying) {
        guard playing != current else { return }
        current = playing
        onChange?(current, isActive)
    }

    public func setAudioPlayers(_ players: [String]) {
        guard players != audioPlayers else { return }
        audioPlayers = players
        onChange?(current, isActive)
    }

    public func toggle() { send(.play) }
    public func next() { send(.next) }
    public func previous() { send(.previous) }
}

/// Posts the system-defined events a keyboard's transport keys post. No permission of its own: it
/// rides on the Accessibility grant Nexus already holds for the window list.
public enum MediaKeys {
    public static func send(_ key: MediaKey) {
        for isDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: UInt(isDown ? 0xA00 : 0xB00))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,                     // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: data1(key, isDown: isDown),
                data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// The key in the high half, the up/down state in the low half — the layout
    /// `NX_KEYTYPE_*` events have always used.
    public static func data1(_ key: MediaKey, isDown: Bool) -> Int {
        Int(key.rawValue) << 16 | ((isDown ? 0xA : 0xB) << 8)
    }
}

/// Which applications are sending audio out right now, from CoreAudio's own per-process answer
/// (`kAudioProcessPropertyIsRunningOutput`, macOS 14.4).
///
/// The device-level question — "is the output device in use" — was tried first and is useless in
/// practice: a browser or a conferencing application holds the device open for hours without making
/// a sound, so the answer is permanently yes. Per process it is exact, and it also names the
/// process, which is what lets a browser tab get an icon rather than a blank row (D75).
///
/// Every process object gets its own listener, because the *list* does not change when a process
/// that already exists starts playing. On a system too old for the process API the answer is simply
/// empty, and the row falls back to the players that publish notifications.
final class AudioOutputMonitor: @unchecked Sendable {
    private let onChange: ([String]) -> Void
    private var processes: [AudioObjectID] = []
    private var listeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var listListener: AudioObjectPropertyListenerBlock?

    init(onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Returns who is playing at the moment it starts, so the first row does not wait for a change.
    @discardableResult
    func start() -> [String] {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.processListChanged()
        }
        listListener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
        )
        rebuildListeners()
        return currentPlayers()
    }

    func stop() {
        if let listListener {
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listListener
            )
            self.listListener = nil
        }
        removeProcessListeners()
    }

    private func processListChanged() {
        rebuildListeners()
        publish()
    }

    private func publish() {
        let players = currentPlayers()
        DispatchQueue.main.async { self.onChange(players) }
    }

    private func rebuildListeners() {
        removeProcessListeners()
        processes = Self.processObjects()
        for process in processes {
            var address = Self.address(kAudioProcessPropertyIsRunningOutput)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.publish() }
            listeners[process] = block
            AudioObjectAddPropertyListenerBlock(process, &address, DispatchQueue.main, block)
        }
    }

    private func removeProcessListeners() {
        for (process, block) in listeners {
            var address = Self.address(kAudioProcessPropertyIsRunningOutput)
            AudioObjectRemovePropertyListenerBlock(process, &address, DispatchQueue.main, block)
        }
        listeners.removeAll()
    }

    /// Bundle identifiers of the processes currently sending audio out, Nexus itself excluded.
    private func currentPlayers() -> [String] {
        let own = ProcessInfo.processInfo.processIdentifier
        var players: [String] = []
        for process in Self.processObjects() where Self.isRunningOutput(process) {
            guard let pid = Self.processIdentifier(of: process), pid != own else { continue }
            guard let identifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            else { continue }
            if !players.contains(identifier) { players.append(identifier) }
        }
        return players
    }

    static func processObjects() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0
        else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr
        else { return [] }
        return objects
    }

    static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        var address = address(kAudioProcessPropertyIsRunningOutput)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    static func processIdentifier(of process: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &pid) == noErr, pid > 0
        else { return nil }
        return pid
    }
}
