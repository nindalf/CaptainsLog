import Foundation

/// Completing a project completes its remaining todos, as in Things. The todos are passed in
/// rather than read from `project.todos`, which can lag behind inserts.
public enum ProjectCompletion {
    public static func complete(_ project: Project, openTodos: [Todo], now: Date = .now) {
        for todo in openTodos where !todo.isCompleted {
            todo.completedDate = now
        }
        project.completedDate = now
    }

    /// Reopens the project only; its todos stay completed.
    public static func reopen(_ project: Project) {
        project.completedDate = nil
    }
}
