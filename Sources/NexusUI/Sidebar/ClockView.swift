import NexusCore
import SwiftUI

/// The clock at the end of the bar: the time over the date, two slots, opening a calendar (M27).
///
/// `TimelineView(.everyMinute)` rather than a `Timer`: it is the platform's own schedule, it stops
/// while the view is off screen, and it lands on the minute rather than drifting a second past it
/// (§65 — nothing here polls).
struct SidebarClockRow: View {
    @Bindable var model: SidebarViewModel

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVertical: Bool { model.appearance.position.isVertical }

    /// Two rows' worth along the bar's axis, the gap between them included — the same "one view
    /// across several rows' extent" the search box and the wide player use (D82).
    private var extent: CGFloat {
        SidebarLayout.sectionExtent(rows: model.clockRowCount, appearance: model.appearance)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(spacing: 1) {
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
            Text(now, format: Date.FormatStyle(date: .numeric, time: .omitted))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .lineLimit(1)
        // A vertical bar is 64 points across and a numeric date in some locales is wider than that.
        // Shrinking it is the only alternative to truncating the year.
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 6)
        .frame(width: isVertical ? nil : extent, height: isVertical ? extent : nil)
        .frame(maxWidth: isVertical ? .infinity : nil, maxHeight: isVertical ? nil : .infinity)
        .background {
            RoundedRectangle(cornerRadius: Design.itemCornerRadius, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear))
        }
        .contentShape(Rectangle())
        .nexusFocusRing(model.focusedRowID == SidebarViewModel.clockRowID)
        .onHover { hovering in
            withAnimation(Design.animation(Design.hover, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
        }
        .nexusRow(onClick: { model.showCalendar?() })
        // One element, not two `Text`s: VoiceOver reading "21:45" and "25/08/2026" as separate rows
        // makes the bar two stops longer for no extra information.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(now, format: .dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue(Text(now, format: .dateTime.hour().minute()))
        .accessibilityHint(String(localized: "Opens the calendar"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.showCalendar?() }
    }
}

/// The calendar's one piece of state, held outside the view so the panel can put it back to today
/// each time it opens — a `@State` inside a view the panel creates once and reuses would still be
/// showing whatever month the last visit wandered off to.
@MainActor
@Observable
final class CalendarViewModel {
    var date = Date()

    func reset() {
        date = Date()
    }
}

/// The calendar the clock opens.
///
/// A graphical `DatePicker` and nothing else: it is the system's own month grid, so the month
/// arrows, the first day of the week, the localisation and the VoiceOver rotor all arrive already
/// working. The selection is thrown away — this is a calendar to look at, not a date to pick.
struct CalendarPopoverView: View {
    @Bindable var model: CalendarViewModel

    var body: some View {
        DatePicker("", selection: $model.date, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(12)
            .frame(width: 280)
            .background(.regularMaterial)
            .accessibilityLabel(String(localized: "Calendar"))
    }
}
