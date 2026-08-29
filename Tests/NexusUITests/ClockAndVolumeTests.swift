import Foundation
import Testing

@testable import NexusCore
@testable import NexusUI

/// The clock and volume rows at the end of the bar (M27): whether they are drawn, what they cost
/// the applications in slots, and where the keyboard finds them.
@Suite("Clock and volume")
@MainActor
struct ClockAndVolumeTests {
    /// A device that only remembers what it was told, so nothing here touches the volume of the
    /// machine running the tests.
    final class FakeDevice: VolumeDevice {
        var hasVolume = true
        var volume: Float = 0.5
        var isMuted = false
    }

    private func makeModel(
        hasVolume: Bool = true,
        wired: Bool = true
    ) -> (SidebarViewModel, ConfigurationController) {
        let controller = ConfigurationController(
            store: InMemoryConfigurationStore(NexusConfiguration()),
            events: EventBus(),
            saveDelay: .zero
        )
        let device = FakeDevice()
        device.hasVolume = hasVolume
        let volume = VolumeService()
        volume.device = device
        volume.refresh()
        let model = SidebarViewModel(
            applications: FakeApplicationService([]),
            configuration: controller,
            events: EventBus(),
            volume: volume
        )
        if wired {
            model.showVolume = {}
            model.showCalendar = {}
        }
        return (model, controller)
    }

    @Test("Both rows are drawn once the popovers are wired up and the setting asks for them")
    func drawnWhenWired() {
        let (model, _) = makeModel()
        #expect(model.showsVolumeRow)
        #expect(model.showsClockRow)
    }

    /// The same bargain the Search row makes: a setting cannot conjure a row whose popover the
    /// composition root has not injected.
    @Test("Neither row is drawn before its popover is injected")
    func hiddenUntilWired() {
        let (model, _) = makeModel(wired: false)
        #expect(!model.showsVolumeRow)
        #expect(!model.showsClockRow)
    }

    @Test("An output device with no volume to set draws no volume row")
    func hiddenWithoutADeviceVolume() {
        let (model, _) = makeModel(hasVolume: false)
        #expect(!model.showsVolumeRow)
        #expect(model.showsClockRow)
    }

    @Test("Switching either off takes its row off the bar")
    func settingsSwitchThemOff() {
        let (model, controller) = makeModel()
        controller.update { $0.general.showClock = false }
        #expect(!model.showsClockRow)
        #expect(model.showsVolumeRow)
        controller.update { $0.general.showVolume = false }
        #expect(!model.showsVolumeRow)
    }

    /// A row that is not there gives its slot back to the applications (D74) — the clock costs two
    /// of them, the volume one.
    @Test("The tail grows by three slots and shrinks back")
    func tailRowCount() {
        let (model, controller) = makeModel()
        let both = model.tailRowCount
        controller.update {
            $0.general.showClock = false
            $0.general.showVolume = false
        }
        #expect(model.tailRowCount == both - 3)
    }

    @Test("The clock is two rows and says so everywhere the layout asks")
    func clockSpansTwoRows() {
        let (model, _) = makeModel()
        #expect(model.clockRowCount == 2)
        #expect(model.sectionRowCounts.suffix(2) == [1, 2])
    }

    /// `SidebarLayout` drops the empty sections, so an index into `sectionRowCounts` is not an
    /// index into what is drawn — the clock's index has to move when the volume is switched off.
    @Test("The clock's section index closes up when the volume row goes")
    func sectionIndicesFollowWhatIsDrawn() {
        let (model, controller) = makeModel()
        let volumeSection = try? #require(model.volumeSectionIndex)
        #expect(model.clockSectionIndex == (volumeSection ?? 0) + 1)
        controller.update { $0.general.showVolume = false }
        #expect(model.volumeSectionIndex == nil)
        #expect(model.clockSectionIndex == volumeSection)
    }

    @Test("The keyboard reaches both rows, at the end, in drawing order")
    func keyboardOrder() {
        let (model, controller) = makeModel()
        #expect(
            model.focusableRowIDs.suffix(2)
                == [SidebarViewModel.volumeRowID, SidebarViewModel.clockRowID]
        )
        controller.update { $0.general.showVolume = false }
        #expect(model.focusableRowIDs.last == SidebarViewModel.clockRowID)
        #expect(!model.focusableRowIDs.contains(SidebarViewModel.volumeRowID))
    }

    @Test("Return on a focused row opens its popover")
    func activatingTheFocusedRow() {
        let (model, _) = makeModel()
        var opened: [String] = []
        model.showVolume = { opened.append("volume") }
        model.showCalendar = { opened.append("calendar") }

        model.beginKeyboardNavigation()
        model.focusLastRow()
        #expect(model.focusedRowID == SidebarViewModel.clockRowID)
        model.activateFocusedRow()
        #expect(opened == ["calendar"])

        model.beginKeyboardNavigation()
        model.focusLastRow()
        model.moveFocus(by: -1)
        #expect(model.focusedRowID == SidebarViewModel.volumeRowID)
        model.activateFocusedRow()
        #expect(opened == ["calendar", "volume"])
    }
}
