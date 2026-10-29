import ArgumentParser
import Foundation

enum CLIDate {
    /// Parses a bare ISO 8601 date (2026-05-05) as local midnight. The formatter's default, UTC,
    /// can be the day before here.
    static func day(_ string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        // The formatter rolls impossible days over (2026-02-30 becomes 2 March), so check it round-trips.
        guard let date = formatter.date(from: string), formatter.string(from: date) == string else {
            throw ValidationError("Invalid date: \(string). Use YYYY-MM-DD")
        }
        return date
    }

    /// Parses YYYY-MM-DDTHH:MM in local time, or a bare day, which keeps `keepingTimeOf`'s time.
    static func dateTime(_ string: String, keepingTimeOf original: Date) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let date = formatter.date(from: string), formatter.string(from: date) == string {
            return date
        }
        guard (try? day(string)) != nil else {
            throw ValidationError("Invalid date: \(string). Use YYYY-MM-DD or YYYY-MM-DDTHH:MM")
        }
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute, .second], from: original)
        return cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: try day(string))!
    }

    /// The half-open range from the start of `from` to the end of `to`, so `--to` includes that
    /// whole day. Missing ends fall back to the defaults.
    static func range(from: String?, to: String?, defaultFrom: Date, defaultTo: Date) throws -> Range<Date> {
        let start = try from.map(day) ?? defaultFrom
        let end = try to.map { try Calendar.current.date(byAdding: .day, value: 1, to: day($0))! } ?? defaultTo
        guard start < end else {
            throw ValidationError("--from must be on or before --to")
        }
        return start..<end
    }

    static var weekAgo: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: .now))!
    }
}
