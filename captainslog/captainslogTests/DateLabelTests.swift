import Foundation
import Testing
import CaptainsLogKit

struct DateLabelTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_GB")
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        return cal
    }()

    private func date(_ day: Int, month: Int = 10, year: Int = 2026, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Thursday 22 Oct 2026.
    private var thursday: Date { date(22, hour: 12) }

    @Test func thisWeekIsWordsThenWeekdays() {
        let labels = (19...25).map { DateLabel.day(date($0), now: thursday, calendar: calendar) }
        #expect(labels == ["Mon", "Tue", "Yesterday", "Today", "Tomorrow", "Sat", "Sun"])
    }

    @Test func otherWeeksAreDates() {
        #expect(DateLabel.day(date(18), now: thursday, calendar: calendar) == "18 Oct")
        #expect(DateLabel.day(date(26), now: thursday, calendar: calendar) == "26 Oct")
        #expect(DateLabel.day(date(18, year: 2025), now: thursday, calendar: calendar) == "18 Oct 2025")
    }

    @Test func nearDaysCrossTheWeekBoundary() {
        let monday = date(26, hour: 12)
        let sunday = date(25, hour: 12)
        #expect(DateLabel.day(date(25), now: monday, calendar: calendar) == "Yesterday")
        #expect(DateLabel.day(date(26), now: sunday, calendar: calendar) == "Tomorrow")
    }

    @Test func dayTimeAndSentence() {
        #expect(DateLabel.dayTime(date(22, hour: 14), now: thursday, calendar: calendar) == "Today 14:00")
        #expect(DateLabel.day(date(21), now: thursday, calendar: calendar, inSentence: true) == "yesterday")
    }

    @Test func headersSpellTheWeekdayOut() {
        #expect(DateLabel.header(date(22), now: thursday, calendar: calendar) == "Today")
        #expect(DateLabel.header(date(19), now: thursday, calendar: calendar) == "Monday 19 Oct")
        #expect(DateLabel.header(date(21, year: 2025), now: thursday, calendar: calendar) == "Tuesday 21 Oct 2025")
    }
}
