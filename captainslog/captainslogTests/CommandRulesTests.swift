import Foundation
import Testing
import CaptainsLogKit

// The rules behind One Day Later/Earlier, and Join Meeting and Open Meeting.
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

    private func meetings(_ events: [CalendarEvent], for purpose: TodaysMeetings.Purpose = .join, at minutes: Double = 0) -> (titles: [String], selected: String?) {
        let list = TodaysMeetings(among: events, for: purpose, now: now.addingTimeInterval(minutes * 60))
        return (list.events.map(\.title), list.selected.map { list.events[$0].title })
    }

    @Test func listsTheWholeDayInStartOrder() {
        let earlier = event("earlier", startsIn: -120)
        let later = event("later", startsIn: 60)
        let current = event("current", startsIn: 0)
        #expect(meetings([later, earlier, current]).titles == ["earlier", "current", "later"])
    }

    @Test func selectsTheMeetingUnderWay() {
        let hour = event("hour", startsIn: 0, lasting: 60)
        let next = event("next", startsIn: 60)
        #expect(meetings([hour, next], at: 0).selected == "hour")
        #expect(meetings([hour, next], at: 59).selected == "hour")
        #expect(meetings([hour, next], at: 60).selected == "next")
        // Overlapping: the latest to start.
        let late = event("late", startsIn: 30, lasting: 15)
        #expect(meetings([hour, late, next], at: 40).selected == "late")
        #expect(meetings([hour, late, next], at: 50).selected == "hour")
    }

    @Test func selectsTheNextBetweenMeetings() {
        let ended = event("ended", startsIn: -60)
        let afternoon = event("afternoon", startsIn: 240)
        #expect(meetings([ended, afternoon]).selected == "afternoon")
        // Nothing left today: the last one.
        #expect(meetings([ended]).selected == "ended")
        #expect(meetings([]).selected == nil)
    }

    @Test func withNoneTodayListsTheNextDayWithMeetings() {
        let dayAfter = event("dayAfter", startsIn: 48 * 60)
        let dayAfterLater = event("dayAfterLater", startsIn: 49 * 60)
        let later = event("later", startsIn: 72 * 60)
        let result = meetings([later, dayAfterLater, dayAfter])
        #expect(result.titles == ["dayAfter", "dayAfterLater"])
        #expect(result.selected == "dayAfter")
        // Any today, even ended, keeps the list on today.
        #expect(meetings([event("ended", startsIn: -60), dayAfter]).titles == ["ended"])
    }

    @Test func joinNeedsALink() {
        let noLink = event("noLink", startsIn: 0, link: false)
        let hidden = event("hidden", startsIn: 2)
        hidden.isHidden = true
        let allDay = event("allDay", startsIn: -600, lasting: 1440)
        allDay.isAllDay = true
        let yesterday = event("yesterday", startsIn: -24 * 60)
        let ended = event("ended", startsIn: -60)
        #expect(meetings([noLink, hidden, allDay, yesterday, ended]).titles == ["ended"])
    }

    @Test func notesNeedSomeoneElseOrExistingNotes() {
        let alone = event("alone", startsIn: 0)
        let noted = event("noted", startsIn: 30, link: false)
        noted.meeting = Meeting(date: noted.startTime, title: "noted")
        let together = event("together", startsIn: 60, link: false)
        together.attendees = [Person(name: "A"), Person(name: "B")]
        #expect(meetings([alone, noted, together], for: .notes).titles == ["noted", "together"])
    }
}
