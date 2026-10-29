import Foundation

/// The app's one date vocabulary. Near days are words (Yesterday, Today, Tomorrow), the rest of
/// this Monday-to-Sunday week is a weekday, anything else a date with the year only when it isn't
/// this year.
public enum DateLabel {
    /// A row's date: "Today", "Mon", "21 Oct", "21 Oct 2025". `inSentence` lowercases the words,
    /// for "Merged yesterday".
    public static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current, inSentence: Bool = false) -> String {
        if let word = nearDay(date, now: now, calendar: calendar) { return inSentence ? word.lowercased() : word }
        if inSameWeek(date, now, calendar: calendar) {
            return date.formatted(style(calendar).weekday(.abbreviated))
        }
        return shortDate(date, now: now, calendar: calendar)
    }

    /// A row's date and time, for things that happen at a time: "Today 9:00", "Mon 14:00".
    public static func dayTime(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        day(date, now: now, calendar: calendar) + " " + date.formatted(style(calendar).hour().minute())
    }

    /// A day group's header: "Today", "Wednesday 22 Oct", "Wednesday 22 Oct 2025".
    public static func header(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if let word = nearDay(date, now: now, calendar: calendar) { return word }
        return date.formatted(style(calendar).weekday(.wide)) + " " + shortDate(date, now: now, calendar: calendar)
    }

    private static func nearDay(_ date: Date, now: Date, calendar: Calendar) -> String? {
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day
        switch offset {
        case -1: return "Yesterday"
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return nil
        }
    }

    private static func inSameWeek(_ date: Date, _ now: Date, calendar: Calendar) -> Bool {
        var monday = calendar
        monday.firstWeekday = 2
        return monday.isDate(date, equalTo: now, toGranularity: .weekOfYear)
    }

    private static func shortDate(_ date: Date, now: Date, calendar: Calendar) -> String {
        let format = style(calendar).day().month(.abbreviated)
        return calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(format)
            : date.formatted(format.year())
    }

    private static func style(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
    }
}
