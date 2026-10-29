import Foundation
import Testing
import CaptainsLogKit

// Which day the Dashboard's agenda shows. Events are built but never inserted.
@Suite(.serialized) @MainActor
struct AgendaTests {
    /// Sunday 25 Oct 2026, 8pm.
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 20))!

    private func event(_ title: String, day offset: Int, hour: Int, allDay: Bool = false, hidden: Bool = false) -> CalendarEvent {
        let cal = Calendar.current
        let start = cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!)!
        let event = CalendarEvent(title: title, startTime: start, endTime: start.addingTimeInterval(1800), externalID: title)
        event.isAllDay = allDay
        event.isHidden = hidden
        return event
    }

    @Test func todayWithEventsIsShownEvenOnceTheyArePast() throws {
        let day = try #require(Agenda.day(among: [event("Tomorrow", day: 1, hour: 9), event("Morning", day: 0, hour: 9)], now: now))
        #expect(day.isToday)
        #expect(day.events.map(\.title) == ["Morning"])
    }

    @Test func anEmptyTodayShowsTheNextDayWithEventsInOrder() throws {
        let events = [event("Late", day: 2, hour: 15), event("Early", day: 2, hour: 9), event("Later", day: 3, hour: 9)]
        let day = try #require(Agenda.day(among: events, now: now))
        #expect(!day.isToday)
        #expect(Calendar.current.isDate(day.date, inSameDayAs: events[0].startTime))
        #expect(day.events.map(\.title) == ["Early", "Late"])
    }

    @Test func allDayAndHiddenEventsDoNotCount() throws {
        let events = [
            event("Holiday", day: 0, hour: 0, allDay: true),
            event("Hidden", day: 0, hour: 10, hidden: true),
            event("Monday", day: 1, hour: 9),
        ]
        let day = try #require(Agenda.day(among: events, now: now))
        #expect(day.events.map(\.title) == ["Monday"])
    }

    @Test func nothingWithinTheHorizonGivesNoDay() {
        #expect(Agenda.day(among: [event("Far", day: 20, hour: 9)], now: now) == nil)
    }
}
