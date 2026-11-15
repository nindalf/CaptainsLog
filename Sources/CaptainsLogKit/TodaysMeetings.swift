import Foundation

/// What Join Meeting and Open Meeting list: the day's meetings, with one selected so the same keys
/// always pick it.
public struct TodaysMeetings {
    public enum Purpose: Hashable, Sendable {
        /// Events with a link.
        case join
        /// Events with someone else in them, or already holding notes.
        case notes
    }

    /// Today's timed, shown events for `purpose`, in start order, earlier ones included. With none
    /// today, the next day that has some.
    public let events: [CalendarEvent]
    /// The one under way (the latest to start, if they overlap), else the next to start, else the
    /// last. Nil only when there are none.
    public let selected: Int?

    public init(among events: [CalendarEvent], for purpose: Purpose, now: Date = .now, calendar: Calendar = .current) {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let candidates = events
            .filter { event in
                guard !event.isAllDay, !event.isHidden, event.startTime >= startOfToday else { return false }
                switch purpose {
                case .join: return event.meetingURL != nil
                case .notes: return event.attendees.count >= 2 || event.meeting != nil || event.interview != nil
                }
            }
            .sorted { $0.startTime < $1.startTime }
        let today = candidates.filter { $0.startTime < endOfToday }
        if today.isEmpty, let first = candidates.first {
            self.events = candidates.filter { calendar.isDate($0.startTime, inSameDayAs: first.startTime) }
        } else {
            self.events = today
        }
        selected = self.events.lastIndex { $0.startTime <= now && $0.endTime > now }
            ?? self.events.firstIndex { $0.startTime > now }
            ?? (self.events.isEmpty ? nil : self.events.count - 1)
    }
}
