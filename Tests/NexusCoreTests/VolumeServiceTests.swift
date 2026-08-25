import Foundation
import Testing

@testable import NexusCore

/// The volume row's arithmetic, with CoreAudio replaced by a device that only remembers what it
/// was told — running these against the real one would move the volume of the machine under test.
@MainActor
struct VolumeServiceTests {
    final class FakeDevice: VolumeDevice {
        var hasVolume = true
        var volume: Float = 0.5
        var isMuted = false
    }

    private func service(_ device: FakeDevice = FakeDevice()) -> VolumeService {
        let service = VolumeService()
        service.device = device
        service.refresh()
        return service
    }

    @Test func readsTheDeviceOnRefresh() {
        let device = FakeDevice()
        device.volume = 0.25
        device.isMuted = true
        let volume = service(device)
        #expect(volume.level == 0.25)
        #expect(volume.isMuted)
        #expect(volume.isAvailable)
    }

    @Test func aDeviceWithoutVolumeReadsZeroAndUnavailable() {
        let device = FakeDevice()
        device.hasVolume = false
        device.volume = 0.8
        let volume = service(device)
        #expect(!volume.isAvailable)
        #expect(volume.level == 0)
    }

    @Test func settingIsClampedToTheUnitInterval() {
        let device = FakeDevice()
        let volume = service(device)
        volume.setLevel(1.7)
        #expect(volume.level == 1)
        #expect(device.volume == 1)
        volume.setLevel(-0.3)
        #expect(volume.level == 0)
        #expect(device.volume == 0)
    }

    /// An out-of-range write is refused outright by CoreAudio rather than clamped, so a device that
    /// reports a level above 1 must not be passed back to it unchanged.
    @Test func aLevelReadAboveOneIsClamped() {
        let device = FakeDevice()
        device.volume = 1.4
        #expect(service(device).level == 1)
    }

    @Test func settingIsIgnoredWhenTheDeviceHasNoVolume() {
        let device = FakeDevice()
        device.hasVolume = false
        let volume = service(device)
        volume.setLevel(0.9)
        #expect(device.volume == 0.5)
        #expect(volume.level == 0)
    }

    /// Raising the volume of a muted device unmutes it: otherwise the slider moves and nothing
    /// comes out.
    @Test func raisingTheVolumeUnmutes() {
        let device = FakeDevice()
        device.isMuted = true
        let volume = service(device)
        volume.setLevel(0.4)
        #expect(!volume.isMuted)
        #expect(!device.isMuted)
    }

    /// Dragging a muted slider to zero is not a request to unmute.
    @Test func draggingToZeroLeavesItMuted() {
        let device = FakeDevice()
        device.isMuted = true
        let volume = service(device)
        volume.setLevel(0)
        #expect(volume.isMuted)
        #expect(device.isMuted)
    }

    @Test func toggleMuteFlipsBothWays() {
        let device = FakeDevice()
        let volume = service(device)
        volume.toggleMute()
        #expect(volume.isMuted)
        #expect(device.isMuted)
        volume.toggleMute()
        #expect(!volume.isMuted)
        #expect(!device.isMuted)
    }

    @Test func theGlyphFollowsTheLevel() {
        let device = FakeDevice()
        let volume = service(device)
        volume.setLevel(0.1)
        #expect(volume.symbolName == "speaker.wave.1.fill")
        volume.setLevel(0.5)
        #expect(volume.symbolName == "speaker.wave.2.fill")
        volume.setLevel(1)
        #expect(volume.symbolName == "speaker.wave.3.fill")
        volume.setMuted(true)
        #expect(volume.symbolName == "speaker.slash.fill")
    }

    @Test func anUnavailableDeviceDrawsTheSlashedGlyph() {
        let device = FakeDevice()
        device.hasVolume = false
        #expect(service(device).symbolName == "speaker.slash")
    }
}
