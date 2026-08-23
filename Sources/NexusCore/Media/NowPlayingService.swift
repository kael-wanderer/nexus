import AppKit
import CoreAudio
import Darwin
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

/// Turns a window title into something worth calling a track.
///
/// The title of the window making the sound is what a player already tells the world: VLC names the
/// file, a browser names the tab, and both are the thing playing. What they add is furniture — the
/// application's own name, the site's name, a file extension — and stripping it is the difference
/// between "Loki S01 - Newmoon21" and "Loki S01 - Newmoon21.mkv — VLC media player".
public enum MediaTitle {
    /// Sites that put their own name on the end of every tab title.
    static let siteSuffixes = [
        "YouTube", "YouTube Music", "Netflix", "Twitch", "SoundCloud", "Spotify", "Vimeo",
        "Disney+", "Prime Video", "Apple TV", "Apple Music", "Bandcamp", "Mixcloud",
    ]

    /// What a browser adds to a window title about the tab rather than about what is playing.
    /// Chrome's is the reason this list exists: its window title is
    /// `<tab> - Audio playing - Google Chrome - <profile>`, and a profile called anything at all
    /// used to stop the trailing strip dead, leaving every one of those words on the row (D89).
    static let browserFurniture = [
        "Audio playing", "Audio muted", "Video playing", "Camera in use", "Microphone in use",
        "Private", "Incognito", "New Tab", "Untitled",
    ]

    static let separators = [" — ", " – ", " - ", " | "]

    static let mediaExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "avi", "webm", "flv", "wmv", "mpg", "mpeg",
        "mp3", "m4a", "flac", "wav", "aac", "ogg", "opus", "aiff", "alac",
    ]

    /// `nil` when nothing is left worth showing — an untitled window, or a title that was only ever
    /// the application's own name.
    public static func clean(_ title: String, applicationName: String?) -> String? {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Cut at the *first* piece of furniture, not the last: everything after the site name or
        // the browser's own note is furniture too, whatever it happens to say. "Track - YouTube -
        // Audio playing - Google Chrome - Cong" is "Track"; "Artist - Song" is left alone, because
        // neither half is furniture.
        if let cut = firstFurnitureBoundary(in: text, applicationName: applicationName) {
            text = String(text[..<cut]).trimmingCharacters(in: .whitespaces)
        }

        // A file name is a title with an extension on it.
        let url = URL(fileURLWithPath: text)
        if mediaExtensions.contains(url.pathExtension.lowercased()) {
            text = url.deletingPathExtension().lastPathComponent
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              text.caseInsensitiveCompare(applicationName ?? "") != .orderedSame
        else { return nil }
        return text
    }

    /// Where the furniture starts: the separator before the first segment that is the application's
    /// name, a known site, or a browser's note about the tab. `nil` when every segment is title.
    static func firstFurnitureBoundary(
        in text: String,
        applicationName: String?
    ) -> String.Index? {
        var boundaries: [Range<String.Index>] = []
        for separator in separators {
            var start = text.startIndex
            while let range = text.range(of: separator, range: start..<text.endIndex) {
                boundaries.append(range)
                start = range.upperBound
            }
        }
        boundaries.sort { $0.lowerBound < $1.lowerBound }

        for (index, boundary) in boundaries.enumerated() {
            let end = index + 1 < boundaries.count ? boundaries[index + 1].lowerBound : text.endIndex
            guard boundary.upperBound <= end else { continue }
            let segment = String(text[boundary.upperBound..<end])
                .trimmingCharacters(in: .whitespaces)
            if isFurniture(segment, applicationName: applicationName) { return boundary.lowerBound }
        }
        return nil
    }

    static func isFurniture(_ segment: String, applicationName: String?) -> Bool {
        if segment.caseInsensitiveCompare(applicationName ?? "\u{0}") == .orderedSame { return true }
        if siteSuffixes.contains(where: { $0.caseInsensitiveCompare(segment) == .orderedSame }) {
            return true
        }
        return browserFurniture.contains { $0.caseInsensitiveCompare(segment) == .orderedSame }
    }
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
    /// Given a bundle identifier, the title of that application's frontmost window — how a player
    /// that publishes nothing still gets a name for what it is playing (D76). Injected because the
    /// window layer is Accessibility's, and this type knows nothing about it.
    @ObservationIgnored public var windowTitle: ((String) async -> String?)?
    /// Called whenever what is playing changes, or whether anything is. Push, because `@Observable`
    /// does not carry across types and a timer to notice a track change would be a timer (§65).
    @ObservationIgnored public var onChange: ((NowPlaying, Bool) -> Void)?

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var audioMonitor: AudioOutputMonitor?
    @ObservationIgnored private var titleTask: Task<Void, Never>?
    @ObservationIgnored private var positionTask: Task<Void, Never>?
    @ObservationIgnored private let control: any MediaPositionControlling
    /// Whether the player is on screen. Position is the one thing in Nexus that is polled, and this
    /// is what keeps it to the seconds somebody is actually looking at it (M16).
    @ObservationIgnored private var isPlayerVisible = false
    @ObservationIgnored private let center: DistributedNotificationCenter

    public init(
        center: DistributedNotificationCenter = .default(),
        control: any MediaPositionControlling = AppleScriptMediaControl()
    ) {
        self.center = center
        self.control = control
    }

    /// A row worth drawing: either a player told us something, or something is making sound and the
    /// controls will reach whoever owns it.
    /// A row worth drawing. A paused player counts: it stopped making sound, but it is still what
    /// the buttons are for, and a row that vanishes on pause cannot be unpaused (D83).
    public var isActive: Bool {
        current.isPlaying || current.hasMetadata || !audioPlayers.isEmpty || isPausedButPresent
    }

    /// A scriptable player that has stopped making sound but still has something loaded.
    private var isPausedButPresent: Bool {
        stickyPlayer != nil && position?.hasTimeline == true
    }

    /// What the row draws when no player published a track: the application making the sound.
    public var audioIsActive: Bool { !audioPlayers.isEmpty }

    /// The title read from the playing application's window, when it publishes no metadata.
    public private(set) var windowDerivedTitle: String?

    /// Where the player is, for the players that will say (M16). `nil` means no timeline, which is
    /// the honest answer for a browser tab.
    public private(set) var position: MediaPosition?
    /// Whether the player says it is playing. Only a scriptable player knows: for everyone else,
    /// making sound is the only evidence there is.
    public private(set) var scriptedIsPlaying: Bool?
    /// The last application known to be playing, kept after the audio stops so that pausing does not
    /// delete the player you were about to unpause (D83).
    public private(set) var stickyPlayer: String?

    /// What the row and the flyout actually show: published metadata when there is any, and
    /// otherwise the playing application's own window title, which is what it is playing.
    public var display: NowPlaying {
        if current.hasMetadata {
            var published = current
            if let scriptedIsPlaying { published.isPlaying = scriptedIsPlaying }
            return published
        }
        guard let player = audioPlayers.first ?? stickyPlayer else { return NowPlaying() }
        return NowPlaying(
            title: windowDerivedTitle,
            artist: Self.applicationName(of: player),
            playerBundleIdentifier: player,
            // Making sound is the evidence for a player that will not say; one that will, says.
            isPlaying: scriptedIsPlaying ?? !audioPlayers.isEmpty
        )
    }

    static func applicationName(of bundleIdentifier: String) -> String? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first?
            .localizedName
    }

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
        titleTask?.cancel()
        titleTask = nil
        positionTask?.cancel()
        positionTask = nil
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
        if let player = players.first {
            // A new player takes over the row, and its own position with it.
            if player != stickyPlayer {
                stickyPlayer = player
                position = nil
                scriptedIsPlaying = nil
                windowDerivedTitle = nil
            }
        } else if !AppleScriptMediaControl.canReportPosition(stickyPlayer ?? "") {
            // Nothing playing, and the last player cannot be asked whether it is merely paused.
            stickyPlayer = nil
            position = nil
            scriptedIsPlaying = nil
            windowDerivedTitle = nil
        }
        onChange?(current, isActive)
        refreshWindowTitle()
        if isPlayerVisible { startPolling() }
    }

    /// Re-reads the playing application's window title. Called when the set of playing applications
    /// changes and when that application's windows change — not on a timer (§65).
    public func refreshWindowTitle() {
        titleTask?.cancel()
        guard !current.hasMetadata, let player = audioPlayers.first, let windowTitle else {
            setWindowTitle(nil)
            return
        }
        titleTask = Task { [weak self] in
            let raw = await windowTitle(player)
            guard !Task.isCancelled, let self else { return }
            let cleaned = raw.flatMap {
                MediaTitle.clean($0, applicationName: Self.applicationName(of: player))
            }
            self.setWindowTitle(cleaned)
        }
    }

    /// One application's windows changed. Only interesting while that application is the one making
    /// the sound.
    public func windowsChanged(_ bundleIdentifier: String) {
        guard audioPlayers.first == bundleIdentifier else { return }
        refreshWindowTitle()
    }

    func setWindowTitle(_ title: String?) {
        guard title != windowDerivedTitle else { return }
        windowDerivedTitle = title
        onChange?(current, isActive)
    }

    // MARK: - Position

    /// The player appeared or went away. Nothing is read while nobody is looking (§65).
    public func setPlayerVisible(_ visible: Bool) {
        guard visible != isPlayerVisible else { return }
        isPlayerVisible = visible
        if visible {
            startPolling()
        } else {
            positionTask?.cancel()
            positionTask = nil
        }
    }

    /// The player a timeline would belong to: whoever published the track, or whoever is making the
    /// sound.
    public var positionPlayer: String? {
        current.hasMetadata
            ? current.playerBundleIdentifier
            : (audioPlayers.first ?? stickyPlayer)
    }

    private func startPolling() {
        positionTask?.cancel()
        guard let player = positionPlayer else {
            setPlayback(nil)
            return
        }
        Log.system.notice("Reading position from \(player, privacy: .public)")
        positionTask = Task { [weak self, control] in
            while !Task.isCancelled {
                let reading = await control.playback(of: player)
                guard !Task.isCancelled else { return }
                self?.setPlayback(reading)
                // One second: a clock that ticks. Anything faster is an AppleScript round trip per
                // frame for no visible gain.
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func setPlayback(_ reading: MediaPlayback?) {
        guard reading?.position != position || reading?.isPlaying != scriptedIsPlaying else { return }
        position = reading?.position
        scriptedIsPlaying = reading?.isPlaying
        // A player that has stopped answering has nothing loaded any more, so the row goes.
        if reading == nil, audioPlayers.isEmpty { stickyPlayer = nil }
        onChange?(current, isActive)
    }

    public func seek(to seconds: Double) {
        guard let player = positionPlayer else { return }
        // Optimistic: the thumb stays where it was dropped rather than snapping back for the second
        // until the next reading.
        if let current = position {
            setPlayback(
                MediaPlayback(
                    position: MediaPosition(position: seconds, duration: current.duration),
                    isPlaying: scriptedIsPlaying ?? true
                )
            )
        }
        Task { [control] in await control.seek(to: seconds, in: player) }
    }

    /// A script where the player has one, a media key where it does not.
    ///
    /// The key path exists for browser tabs, which no dictionary covers. The script path exists
    /// because a media key is a request to whoever macOS thinks owns playback — which is not always
    /// the player on the row, and in VLC's case is often nobody at all (D83).
    public func toggle() { transport(.playPause, fallback: .play) }
    public func next() { transport(.next, fallback: .next) }
    public func previous() { transport(.previous, fallback: .previous) }

    private func transport(_ command: MediaTransport, fallback key: MediaKey) {
        guard let player = positionPlayer,
              AppleScriptMediaControl.canReportPosition(player)
        else {
            send(key)
            return
        }
        Task { [weak self, control] in
            let handled = await control.command(command, in: player)
            if !handled { self?.send(key) }
            // The state the player reports is the truth, and it just changed.
            self?.refreshPlaybackNow()
        }
    }

    /// One reading, right now, without waiting for the next tick of the poll.
    private func refreshPlaybackNow() {
        guard let player = positionPlayer else { return }
        Task { [weak self, control] in
            let reading = await control.playback(of: player)
            self?.setPlayback(reading)
        }
    }
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

    /// Bundle identifiers of the applications currently sending audio out, Nexus itself excluded.
    private func currentPlayers() -> [String] {
        let own = ProcessInfo.processInfo.processIdentifier
        var players: [String] = []
        for process in Self.processObjects() where Self.isRunningOutput(process) {
            guard let pid = Self.processIdentifier(of: process), pid != own else { continue }
            guard let identifier = Self.owningBundleIdentifier(of: pid) else { continue }
            if !players.contains(identifier) { players.append(identifier) }
        }
        return players
    }

    /// The application a sound belongs to, which is often not the process making it (D89).
    ///
    /// A browser plays media in a helper — Chrome's renderer, Safari's GPU process — and a helper
    /// is not an `NSRunningApplication`, so it has no bundle identifier of its own and the player
    /// used to be dropped on the floor: YouTube in Chrome produced no row at all. Two things do
    /// know who owns it: the helper's executable lives *inside* the owning bundle, and its parent
    /// process is usually the application itself.
    static func owningBundleIdentifier(of pid: pid_t) -> String? {
        if let direct = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
            return direct
        }
        if let fromBundle = bundleIdentifier(containingExecutableOf: pid) { return fromBundle }
        guard let parent = parentProcess(of: pid) else { return nil }
        return NSRunningApplication(processIdentifier: parent)?.bundleIdentifier
    }

    /// The outermost `.app` on the process's executable path. Outermost, because a helper sits
    /// inside the application that owns it — `Google Chrome.app/…/Google Chrome Helper.app` has to
    /// answer "Chrome", not "Chrome Helper".
    static func bundleIdentifier(containingExecutableOf pid: pid_t) -> String? {
        guard let path = executablePath(of: pid) else { return nil }
        var url = URL(fileURLWithPath: path)
        var bundles: [URL] = []
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" { bundles.append(url) }
            url = url.deletingLastPathComponent()
        }
        for bundle in bundles.reversed() {
            if let identifier = Bundle(url: bundle)?.bundleIdentifier { return identifier }
        }
        return nil
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * 1_024)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer[..<Int(length)], as: UTF8.self)
    }

    /// `nil` for a process whose parent is `launchd`, which owns nothing in particular.
    static func parentProcess(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0
        else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 1 ? parent : nil
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
