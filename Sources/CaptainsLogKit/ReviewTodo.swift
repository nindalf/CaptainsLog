import Foundation

/// The "Review PR" todo filed from a review request's context menu.
public enum ReviewTodo {
    static let maxTitleLength = 60

    public static func title(for pr: PullRequest) -> String {
        let prTitle = pr.title.trimmingCharacters(in: .whitespaces)
        guard prTitle.count > maxTitleLength else { return "Review PR \(prTitle)" }
        let clipped = prTitle.prefix(maxTitleLength).trimmingCharacters(in: .whitespaces)
        return "Review PR \(clipped)…"
    }

    /// An uninserted todo for today, above every other open todo, with the PR's URL as its notes.
    public static func make(for pr: PullRequest, among openTodos: [Todo], now: Date = .now, calendar: Calendar = .current) -> Todo {
        let todo = Todo(title: title(for: pr))
        todo.notes = pr.url.absoluteString
        todo.schedule(on: now, calendar: calendar)
        todo.sortOrder = TodoOrdering.topSortOrder(among: openTodos)
        return todo
    }
}
