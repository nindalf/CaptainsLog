import Foundation
import Testing
import CaptainsLogKit

// Todos are built but never inserted, so no container is needed.
@Suite(.serialized) @MainActor
struct TodoOrderingTests {
    private func todos(_ orders: [Int]) -> [Todo] {
        orders.enumerated().map { index, order in
            let todo = Todo(title: "t\(index)")
            todo.sortOrder = order
            return todo
        }
    }

    @Test func tiedValuesAreRenumberedInTheGivenOrder() {
        let items = todos([0, 0, 0])
        #expect(TodoOrdering.makeUnique(items))
        #expect(items.map(\.sortOrder) == [0, 1, 2])
    }

    @Test func uniqueValuesAreLeftAlone() {
        let items = todos([-3, 5, 9])
        #expect(!TodoOrdering.makeUnique(items))
        #expect(items.map(\.sortOrder) == [-3, 5, 9])
    }

    @Test func swappingNeighboursReordersOnceValuesAreUnique() {
        let items = todos([0, 0, 0])
        TodoOrdering.makeUnique(items)
        let first = items[0].sortOrder
        items[0].sortOrder = items[1].sortOrder
        items[1].sortOrder = first
        #expect(items.sorted { $0.sortOrder < $1.sortOrder }.map(\.title) == ["t1", "t0", "t2"])
    }

    @Test func topIsAboveEveryTodo() {
        #expect(TodoOrdering.topSortOrder(among: todos([4, -2, 7])) == -3)
        #expect(TodoOrdering.topSortOrder(among: []) == -1)
    }
}
