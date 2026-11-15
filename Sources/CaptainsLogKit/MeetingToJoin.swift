import Foundation

extension CalendarEvent {
    /// How long into a meeting Join still offers it, rather than starting from the next one.
    public static let joinGrace: TimeInterval = 10 * 60

    /// What Join offers outside a meeting: today's timed, shown events with a link, in start order,
    /// from one that started under `joinGrace` ago, else from the next.
    public static func joinable(among events: [CalendarEvent], now: Date = .now, calendar: Calendar = .current) -> [CalendarEvent] {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let earliest = now.addingTimeInterval(-joinGrace)
        return events
            .filter {
                !$0.isAllDay && !$0.isHidden && $0.meetingURL != nil
                    && $0.startTime >= earliest && $0.startTime < endOfToday && $0.endTime > now
            }
            .sorted { $0.startTime < $1.startTime }
    }
}
