import SwiftUI
import SwiftData
import CaptainsLogKit

struct CalendarWeekView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Navigator.self) private var navigator
    @Environment(AppSettings.self) private var settings

    @Query(filter: #Predicate<CalendarEvent> { !$0.isHidden }, sort: \CalendarEvent.startTime)
    private var allEvents: [CalendarEvent]

    @State private var displayedWeekStart: Date = mondayOfCurrentWeek()
    @State private var unlinkedEvent: CalendarEvent?
    /// Opens on the working day, a little above its first hour so that hour's label shows.
    /// Kept across weeks, as switching week shouldn't jump the view.
    @State private var scrollPosition = ScrollPosition(
        y: CGFloat(TimeGridConstants.workdayStartHour - TimeGridConstants.startHour) * TimeGridConstants.hourHeight - 12
    )

    private let calendar = Calendar.current

    private var dayCount: Int {
        settings.showWeekends ? 7 : 5
    }

    private var weekEnd: Date {
        calendar.date(byAdding: .day, value: dayCount, to: displayedWeekStart)!
    }

    private var allDayEvents: [CalendarEvent] {
        // All-day events that overlap the displayed week (handles multi-day spans)
        allEvents.filter { $0.isAllDay && $0.startTime < weekEnd && $0.endTime > displayedWeekStart }
    }

    private var timedEvents: [CalendarEvent] {
        // Timed events whose start falls within the displayed week
        allEvents.filter { !$0.isAllDay && $0.startTime >= displayedWeekStart && $0.startTime < weekEnd }
    }

    var body: some View {
        VStack(spacing: 0) {
            WeekHeaderView(
                weekStart: displayedWeekStart,
                dayCount: dayCount,
                onPrevWeek: { shiftWeek(by: -1) },
                onNextWeek: { shiftWeek(by: 1) },
                onToday: { displayedWeekStart = Self.mondayOfCurrentWeek() }
            )
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            AllDayBandView(
                events: allDayEvents,
                weekStart: displayedWeekStart,
                dayCount: dayCount,
                onTap: { handleEventTap($0) }
            )
            .fixedSize(horizontal: false, vertical: true)

            if !allDayEvents.isEmpty { Divider() }

            ScrollView(.vertical) {
                TimeGridView(
                    events: timedEvents,
                    weekStart: displayedWeekStart,
                    dayCount: dayCount,
                    onTap: { handleEventTap($0) }
                )
            }
            .scrollPosition($scrollPosition)
            .frame(maxHeight: .infinity)
        }
        .popover(item: $unlinkedEvent) { event in
            CalendarEventPopover(event: event) { action in
                handleEventAction(event, action: action)
                unlinkedEvent = nil
            }
        }
        .onKeyPress(.leftArrow) {
            shiftWeek(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            shiftWeek(by: 1)
            return .handled
        }
    }

    private func handleEventTap(_ event: CalendarEvent) {
        if event.meeting != nil || event.interview != nil {
            navigator.openEvent(event)
        } else {
            unlinkedEvent = event
        }
    }

    private func shiftWeek(by weeks: Int) {
        if let newStart = calendar.date(byAdding: .weekOfYear, value: weeks, to: displayedWeekStart) {
            displayedWeekStart = newStart
        }
    }

    private func handleEventAction(_ event: CalendarEvent, action: CalendarEventPopover.CalendarEventAction) {
        switch action {
        case .createMeeting:
            event.createMeeting(in: modelContext)
            try? modelContext.save()
            navigator.openEvent(event)
        case .hide:
            event.isHidden = true
            try? modelContext.save()
        case .removed:
            event.deleteWithEmptyStubs(in: modelContext)
            try? modelContext.save()
        }
    }

    static func mondayOfCurrentWeek() -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = cal.component(.weekday, from: today)
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat
        let daysFromMonday = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: today)!
        // On weekends, show the upcoming work week instead
        if weekday == 1 || weekday == 7 {
            return cal.date(byAdding: .day, value: 7, to: monday)!
        }
        return monday
    }
}

#Preview {
    CalendarWeekView()
        .previewEnvironment()
        .frame(height: 700)
}
