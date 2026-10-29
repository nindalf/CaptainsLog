import Foundation
import Testing
import CaptainsLogKit
@testable import Captain_s_Log

// Todos and people are built but never inserted, so no container is needed.
@Suite(.serialized) @MainActor
struct TodoPeopleGroupTests {
    private let priya = Person(name: "Priya Patel")
    private let sarah = Person(name: "Sarah Lin")

    private func todo(_ title: String, _ people: [Person] = []) -> Todo {
        let todo = Todo(title: title)
        todo.people = people
        return todo
    }

    @Test func oneSectionPerSetOfPeopleWithSharedTodosBetween() {
        let groups = TodoPeopleGroup.group([
            todo("a", [sarah]), todo("b", [sarah, priya]), todo("c", [priya]), todo("d", [sarah]),
        ])

        #expect(groups.map(\.label) == ["Priya Patel", "Priya Patel, Sarah Lin", "Sarah Lin"])
        #expect(groups[2].todos.map(\.title) == ["a", "d"])
    }

    @Test func untaggedTodosAreLeftOut() {
        #expect(TodoPeopleGroup.group([todo("a")]).isEmpty)
    }

    @Test func todosTaggingSomeoneAreInThePeopleList() {
        #expect(SmartList.people.contains(todo("a", [priya])))
        #expect(!SmartList.people.contains(todo("b")))
        let done = todo("c", [priya])
        done.completedDate = .now
        #expect(!SmartList.people.contains(done))
        // Never a home list.
        #expect(SmartList.of(todo("d", [priya])) == .inbox)
    }

    @Test func dragsStayInsideTheSection() {
        let a = UUID(), b = UUID(), c = UUID()
        // The dragged todo was at index 2, below `a`, and has been taken out.
        let items: [TodoListItem] = [.group("Priya"), .todo(a), .group("Sarah"), .todo(b), .todo(c)]
        #expect(TodoPeopleGroup.dropRange(at: 2, in: items) == 1...2)
        // Dragged from the last section.
        #expect(TodoPeopleGroup.dropRange(at: 4, in: items) == 3...5)
    }
}
