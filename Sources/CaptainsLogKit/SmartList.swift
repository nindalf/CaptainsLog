import Foundation

/// Things-style lists. `of` gives a todo's one home list: trashed todos in the Trash, completed ones
/// in Completed (the Logbook in Things), dated todos in Today (on or before today) or Upcoming, then Someday, then Anytime
/// for undated todos in a project, and the Inbox for the rest. Anytime also shows every dated todo.
/// People (titled By person) is never a home list: it shows every open todo that tags someone, by who it tags.
public enum SmartList: String, CaseIterable, Codable, Sendable {
    case inbox, today, upcoming, anytime, someday, people, logbook, trash

    public var title: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .anytime: "Anytime"
        case .someday: "Someday"
        case .people: "By person"
        case .logbook: "Completed"
        case .trash: "Trash"
        }
    }

    public var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .today: "star"
        case .upcoming: "calendar"
        case .anytime: "square.stack"
        case .someday: "archivebox"
        case .people: "person.2"
        case .logbook: "checkmark.circle"
        case .trash: "trash"
        }
    }

    /// Lists a new todo can be created in. Anytime and People have nothing to file a new todo there
    /// by: they show todos for their project or date, or for the people they tag.
    public var acceptsTodos: Bool { ![.logbook, .trash, .anytime, .people].contains(self) }

    public static func of(_ todo: Todo, now: Date = .now, calendar: Calendar = .current) -> SmartList {
        if todo.isTrashed { return .trash }
        if todo.isCompleted { return .logbook }
        if let date = todo.dueDate {
            return calendar.startOfDay(for: date) <= calendar.startOfDay(for: now) ? .today : .upcoming
        }
        if todo.schedule == .someday { return .someday }
        return todo.project == nil ? .inbox : .anytime
    }

    /// Whether this list shows the todo: its home list, Anytime for dated todos too, and People for
    /// open todos that tag someone.
    public func contains(_ todo: Todo, now: Date = .now, calendar: Calendar = .current) -> Bool {
        if self == .people { return !todo.isTrashed && !todo.isCompleted && !todo.people.isEmpty }
        let home = Self.of(todo, now: now, calendar: calendar)
        if self == .anytime { return [.anytime, .today, .upcoming].contains(home) }
        return home == self
    }

    /// Set the fields that put an open todo in this list, as a new todo created there. Today and
    /// Upcoming pick today and tomorrow; Inbox and Someday clear the date. No-op for Anytime, which
    /// follows from a project or date, and for the Logbook and Trash, which have their own actions
    /// (complete, `moveToTrash`).
    public func move(_ todo: Todo, now: Date = .now, calendar: Calendar = .current) {
        switch self {
        case .inbox: todo.setUndated(.inbox)
        case .someday: todo.setUndated(.someday)
        case .today: todo.schedule(on: now, calendar: calendar)
        case .upcoming:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            todo.schedule(on: tomorrow, calendar: calendar)
        case .anytime, .people, .logbook, .trash: break
        }
    }
}

extension Todo {
    /// Give the todo a date. Resets the schedule to anytime, so clearing the date later sends it
    /// to Anytime rather than back to the Inbox or Someday.
    public func schedule(on date: Date, calendar: Calendar = .current) {
        dueDate = calendar.startOfDay(for: date)
        schedule = .anytime
    }

    public func setUndated(_ schedule: TodoSchedule) {
        dueDate = nil
        self.schedule = schedule
    }

    public func moveToTrash(now: Date = .now) {
        trashedDate = now
    }

    /// Back to whichever list its date, schedule and completion put it in before it was trashed.
    public func restoreFromTrash() {
        trashedDate = nil
    }

    public func reopen() {
        completedDate = nil
        completedInMeeting = nil
    }

    /// Reopening clears the completion date and completing again stamps today, so reopening
    /// anything completed before today asks first.
    public static func reopenNeedsConfirmation(_ todos: [Todo], now: Date = .now, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        return todos.contains { $0.completedDate.map { $0 < today } ?? false }
    }
}
