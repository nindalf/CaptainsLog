import Foundation

/// A todo's "When", as the When popover offers it: a day, Someday, or unset (Inbox or Anytime).
public enum TodoWhen: Hashable, Sendable {
    /// Start of the day.
    case day(Date)
    case someday
    case unset

    public static func of(_ todo: Todo, calendar: Calendar = .current) -> TodoWhen {
        if let due = todo.dueDate { return .day(calendar.startOfDay(for: due)) }
        return todo.schedule == .someday ? .someday : .unset
    }

    public func apply(to todo: Todo, calendar: Calendar = .current) {
        switch self {
        case .day(let date): todo.schedule(on: date, calendar: calendar)
        case .someday: todo.setUndated(.someday)
        case .unset: todo.setUndated(.inbox)
        }
    }

    /// A day later or earlier, counting from today at the earliest and never landing before it.
    /// Undated and Someday count as today going later, and stay put going earlier.
    public func shifted(byDays days: Int, today: Date, calendar: Calendar = .current) -> TodoWhen {
        let today = calendar.startOfDay(for: today)
        let from: Date
        switch self {
        case .day(let date): from = date
        case .someday, .unset:
            guard days > 0 else { return self }
            from = today
        }
        let shifted = calendar.date(byAdding: .day, value: days, to: max(from, today)) ?? from
        return .day(max(shifted, today))
    }

    /// The When shared by every todo, or nil when they differ.
    public static func common(to todos: [Todo], calendar: Calendar = .current) -> TodoWhen? {
        let whens = Set(todos.map { of($0, calendar: calendar) })
        return whens.count == 1 ? whens.first : nil
    }
}
