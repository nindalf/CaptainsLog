import Foundation

/// `sortOrder` is one order across all open todos; each smart list shows a slice of it. Reordering
/// swaps or redistributes values within a list, which only works while the values are unique.
public enum TodoOrdering {
    /// The `sortOrder` that puts a new todo above every other.
    public static func topSortOrder(among todos: [Todo]) -> Int {
        (todos.map(\.sortOrder).min() ?? 0) - 1
    }

    /// Renumber `todos` 0, 1, 2... in the given order if any share a `sortOrder`. Pass them in
    /// display order so the renumbering keeps what is on screen. Returns whether anything changed.
    @discardableResult
    public static func makeUnique(_ todos: [Todo]) -> Bool {
        guard Set(todos.map(\.sortOrder)).count < todos.count else { return false }
        for (index, todo) in todos.enumerated() {
            todo.sortOrder = index
        }
        return true
    }
}
