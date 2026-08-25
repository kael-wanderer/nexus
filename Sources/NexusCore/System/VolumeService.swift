import AudioToolbox
import CoreAudio
import Foundation

/// The system output volume, as much of it as a bar needs: what it is, set it, mute it (M27).
///
/// Push, not polled (§65): the level also changes from the keyboard's volume keys and the menu
/// bar's own slider, and both arrive here as CoreAudio property listeners.
///
/// The device it talks to is the *default output* device, re-read on every access rather than
/// cached — headphones being plugged in changes which device that is, and a cached ID would go on
/// setting the volume of one nobody is listening to.
@MainActor
@Observable
public final class VolumeService {
    /// 0…1. Reads 0 on a device with no volume control at all (some HDMI and aggregate devices),
    /// which is also the case `isAvailable` reports.
    public private(set) var level: Float = 0
    public private(set) var isMuted = false
    /// Whether the default output device answers the volume properties at all. When it does not,
    /// the bar draws the row disabled rather than a slider that does nothing.
    public private(set) var isAvailable = false

    /// Injected so tests do not move the machine's actual volume.
    @ObservationIgnored var device: any VolumeDevice = CoreAudioVolumeDevice()

    @ObservationIgnored private var listener: VolumeListener?

    public init() {}

    /// Reads the current state and starts listening. Safe to call twice.
    public func start() {
        refresh()
        guard listener == nil else { return }
        listener = VolumeListener { [weak self] in self?.refresh() }
        listener?.start()
    }

    public func stop() {
        listener?.stop()
        listener = nil
    }

    deinit {
        listener?.stop()
    }

    /// Re-reads the device. Called by the listener; also useful directly after a set, because a
    /// device may clamp or quantise what it was given.
    public func refresh() {
        isAvailable = device.hasVolume
        level = isAvailable ? device.volume.clampedToUnitInterval : 0
        isMuted = device.isMuted
    }

    /// `newValue` is clamped: a slider cannot send an out-of-range value, but an out-of-range one
    /// makes CoreAudio fail the write outright rather than clamp it itself.
    public func setLevel(_ newValue: Float) {
        guard isAvailable else { return }
        let clamped = newValue.clampedToUnitInterval
        device.volume = clamped
        level = clamped
        // Raising the volume on a muted device is the same gesture as unmuting it: leaving it muted
        // would move a slider that makes no sound.
        if isMuted, clamped > 0 {
            device.isMuted = false
            isMuted = false
        }
    }

    public func setMuted(_ newValue: Bool) {
        device.isMuted = newValue
        isMuted = newValue
    }

    public func toggleMute() {
        setMuted(!isMuted)
    }

    /// The speaker glyph for the current state: SF Symbols draws one wave per third of the range,
    /// so this is the level rounded to which of them it falls in.
    public var symbolName: String {
        guard isAvailable else { return "speaker.slash" }
        if isMuted || level <= 0 { return "speaker.slash.fill" }
        switch level {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

extension Float {
    var clampedToUnitInterval: Float { min(max(self, 0), 1) }
}

/// The part that talks to CoreAudio, behind a protocol so the service above can be tested without
/// changing the volume of the machine running the tests.
protocol VolumeDevice: AnyObject {
    var hasVolume: Bool { get }
    var volume: Float { get set }
    var isMuted: Bool { get set }
}

final class CoreAudioVolumeDevice: VolumeDevice {
    /// The *virtual main* volume, not `kAudioDevicePropertyVolumeScalar`: the latter is per-channel
    /// and absent on plenty of devices, while this one is the single fader the menu bar moves.
    ///
    /// Built fresh on each call rather than held in a `static`: every CoreAudio call takes the
    /// address `inout`, so a shared one would be mutable global state.
    static func volumeAddress() -> AudioObjectPropertyAddress {
        outputAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
    }

    static func muteAddress() -> AudioObjectPropertyAddress {
        outputAddress(kAudioDevicePropertyMute)
    }

    private static func outputAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Re-read every time: which device this is changes when headphones are plugged in.
    static var defaultOutputDevice: AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr ? device : AudioObjectID(kAudioObjectUnknown)
    }

    var hasVolume: Bool {
        let device = Self.defaultOutputDevice
        guard device != AudioObjectID(kAudioObjectUnknown) else { return false }
        var address = Self.volumeAddress()
        return AudioObjectHasProperty(device, &address)
    }

    var volume: Float {
        get {
            let device = Self.defaultOutputDevice
            guard device != AudioObjectID(kAudioObjectUnknown) else { return 0 }
            var address = Self.volumeAddress()
            var value: Float = 0
            var size = UInt32(MemoryLayout<Float>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return status == noErr ? value : 0
        }
        set {
            let device = Self.defaultOutputDevice
            guard device != AudioObjectID(kAudioObjectUnknown) else { return }
            var address = Self.volumeAddress()
            var value = newValue
            let size = UInt32(MemoryLayout<Float>.size)
            let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
            if status != noErr {
                Log.system.error("Setting the volume failed: \(status, privacy: .public)")
            }
        }
    }

    var isMuted: Bool {
        get {
            let device = Self.defaultOutputDevice
            guard device != AudioObjectID(kAudioObjectUnknown) else { return false }
            var address = Self.muteAddress()
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return status == noErr && value != 0
        }
        set {
            let device = Self.defaultOutputDevice
            guard device != AudioObjectID(kAudioObjectUnknown) else { return }
            // ponytail: a device with no mute property is left alone rather than emulated by
            // setting the volume to zero — that would lose the level to restore on unmute.
            var address = Self.muteAddress()
            guard AudioObjectHasProperty(device, &address) else { return }
            var value: UInt32 = newValue ? 1 : 0
            let size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        }
    }
}

/// Listens for volume, mute and default-device changes.
///
/// The device listeners are rebuilt whenever the default output device changes, because the volume
/// of the old device is not the volume of the new one and nothing re-reads on its own.
private final class VolumeListener: @unchecked Sendable {
    private let onChange: () -> Void
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private var defaultBlock: AudioObjectPropertyListenerBlock?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain
        )
    }

    func start() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.defaultDeviceChanged()
        }
        defaultBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
        )
        attachDeviceListeners()
    }

    func stop() {
        if let defaultBlock {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, defaultBlock
            )
            self.defaultBlock = nil
        }
        detachDeviceListeners()
    }

    private func defaultDeviceChanged() {
        detachDeviceListeners()
        attachDeviceListeners()
        onChange()
    }

    private func attachDeviceListeners() {
        device = CoreAudioVolumeDevice.defaultOutputDevice
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onChange()
        }
        deviceBlock = block
        for selector in [
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            kAudioDevicePropertyMute,
        ] {
            var address = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
            AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block)
        }
    }

    private func detachDeviceListeners() {
        guard let deviceBlock, device != AudioObjectID(kAudioObjectUnknown) else { return }
        for selector in [
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            kAudioDevicePropertyMute,
        ] {
            var address = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
            AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, deviceBlock)
        }
        self.deviceBlock = nil
        device = AudioObjectID(kAudioObjectUnknown)
    }
}
