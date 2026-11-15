import Foundation
import Testing
import CaptainsLogKit

// The rules behind One Day Later/Earlier and Join Meeting.
// Events are built but never inserted, so no container is needed.
@Suite(.serialized) @MainActor
struct CommandRulesTests {
    /// Tuesday 17 Nov 2026, 10:00.
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10))!
    private let calendar = Calendar.current

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    @Test func dayLaterAndEarlier() {
        #expect(TodoWhen.day(day(2)).shifted(byDays: 1, today: now) == .day(day(3)))
        #expect(TodoWhen.day(day(2)).shifted(byDays: -1, today: now) == .day(day(1)))
        // Today can't go earlier, and an overdue todo counts from today.
        #expect(TodoWhen.day(day(0)).shifted(byDays: -1, today: now) == .day(day(0)))
        #expect(TodoWhen.day(day(-3)).shifted(byDays: 1, today: now) == .day(day(1)))
        #expect(TodoWhen.day(day(-3)).shifted(byDays: -1, today: now) == .day(day(0)))
        // Undated counts as today going later, and stays put going earlier.
        #expect(TodoWhen.unset.shifted(byDays: 1, today: now) == .day(day(1)))
        #expect(TodoWhen.someday.shifted(byDays: 1, today: now) == .day(day(1)))
        #expect(TodoWhen.unset.shifted(byDays: -1, today: now) == .unset)
        #expect(TodoWhen.someday.shifted(byDays: -1, today: now) == .someday)
    }

    private func event(_ title: String, startsIn minutes: Double, lasting duration: Double = 30, link: Bool = true) -> CalendarEvent {
        let start = now.addingTimeInterval(minutes * 60)
        let event = CalendarEvent(title: title, startTime: start, endTime: start.addingTimeInterval(duration * 60), externalID: title)
        event.meetingURL = link ? URL(string: "https://meet.example.com/\(title)") : nil
        return event
    }

    @Test func joinOffersTodaysMeetingsFromTheCurrentOne() {
        let started = event("started", startsIn: -5)
        let later = event("later", startsIn: 55)
        let next = event("next", startsIn: 25)
        #expect(CalendarEvent.joinable(among: [later, started, next], now: now).map(\.title) == ["started", "next", "later"])
    }

    @Test func joinStartsFromTheNextMeetingTenMinutesIn() {
        let ongoing = event("ongoing", startsIn: -11, lasting: 60)
        let next = event("next", startsIn: 5)
        #expect(CalendarEvent.joinable(among: [ongoing, next], now: now).map(\.title) == ["next"])
    }

    @Test func joinSkipsWhatCantBeJoined() {
        let ended = event("ended", startsIn: -8, lasting: 5)
        let noLink = event("noLink", startsIn: 1, link: false)
        let hidden = event("hidden", startsIn: 2)
        hidden.isHidden = true
        let allDay = event("allDay", startsIn: -600, lasting: 1440)
        allDay.isAllDay = true
        let tomorrow = event("tomorrow", startsIn: 24 * 60)
        let joinable = event("joinable", startsIn: 120)
        #expect(CalendarEvent.joinable(among: [ended, noLink, hidden, allDay, tomorrow, joinable], now: now).map(\.title) == ["joinable"])
    }
}
