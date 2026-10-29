import Foundation

/// The day the Dashboard's agenda shows: today if it has timed events, else the next day that
/// does, looking at most `horizon` days ahead.
public enum Agenda {
    public struct Day {
        public let date: Date
        public let events: [CalendarEvent]
        public let isToday: Bool
    }

    public static func day(
        among events: [CalendarEvent],
        now: Date = .now,
        horizon: Int = 14,
        calendar: Calendar = .current
    ) -> Day? {
        let timed = events.filter { !$0.isAllDay && !$0.isHidden }
        let today = calendar.startOfDay(for: now)
        for offset in 0...horizon {
            guard let start = calendar.date(byAdding: .day, value: offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let onDay = timed
                .filter { $0.startTime >= start && $0.startTime < end }
                .sorted { $0.startTime < $1.startTime }
            if !onDay.isEmpty { return Day(date: start, events: onDay, isToday: offset == 0) }
        }
        return nil
    }
}
