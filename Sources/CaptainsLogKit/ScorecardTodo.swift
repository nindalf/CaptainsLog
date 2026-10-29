import Foundation

/// The "Submit scorecard" todo an interview gets when the first text is written into it.
public enum ScorecardTodo {
    public static func title(for interview: Interview) -> String {
        let name = interview.candidateName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Submit scorecard" : "Submit scorecard for \(name)"
    }

    /// Whether an edit that took the interview from `hadText` to its current state should add the
    /// todo: only the first text, and only while no todo is filed against the interview, trashed
    /// and completed ones included, so deleting it doesn't bring it back.
    public static func isDue(hadText: Bool, interview: Interview, linkedTodos: [Todo]) -> Bool {
        !hadText && interview.hasWrittenText && linkedTodos.isEmpty
    }

    /// An uninserted todo for today, above every other open todo. Private if the interview is.
    public static func make(for interview: Interview, among openTodos: [Todo], now: Date = .now, calendar: Calendar = .current) -> Todo {
        let todo = Todo(title: title(for: interview))
        todo.schedule(on: now, calendar: calendar)
        todo.sortOrder = TodoOrdering.topSortOrder(among: openTodos)
        todo.isPrivate = interview.isPrivate
        return todo
    }
}
