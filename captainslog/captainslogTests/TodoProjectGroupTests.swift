import Foundation
import Testing
import CaptainsLogKit
@testable import Captain_s_Log

// Todos and projects are built but never inserted, so no container is needed.
@Suite(.serialized) @MainActor
struct TodoProjectGroupTests {
    private func todo(_ title: String, _ project: Project? = nil) -> Todo {
        let todo = Todo(title: title)
        todo.project = project
        return todo
    }

    @Test func looseTodosComeFirstThenProjectsInColumnOrder() {
        let second = Project(name: "A second")
        second.sortOrder = 1
        let first = Project(name: "Z first")
        first.sortOrder = 0
        let groups = TodoProjectGroup.group([
            todo("a", second), todo("b"), todo("c", first), todo("d", second),
        ])

        #expect(groups.map { $0.project?.name } == [nil, "Z first", "A second"])
        #expect(groups[2].todos.map(\.title) == ["a", "d"])
    }

    @Test func thereIsNoLooseGroupWithoutLooseTodos() {
        let groups = TodoProjectGroup.group([todo("a", Project(name: "P"))])
        #expect(groups.map { $0.project?.name } == ["P"])
    }

    @Test func aDroppedTodoJoinsTheHeadingAboveIt() {
        let todo = UUID(), other = UUID(), first = UUID(), second = UUID()
        let items: [TodoListItem] = [.todo(other), .heading(first), .todo(UUID()), .heading(second), .todo(todo)]

        #expect(TodoListItem.projectID(above: todo, in: items) == second)
        #expect(TodoListItem.projectID(above: other, in: items) == nil)
    }
}
