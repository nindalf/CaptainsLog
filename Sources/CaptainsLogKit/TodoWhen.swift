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

    /// The When shared by every todo, or nil when they differ.
    public static func common(to todos: [Todo], calendar: Calendar = .current) -> TodoWhen? {
        let whens = Set(todos.map { of($0, calendar: calendar) })
        return whens.count == 1 ? whens.first : nil
    }
}
