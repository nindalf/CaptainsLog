import Foundation
import CaptainsLogKit

/// The People list's sections: one per set of tagged people, so a todo tagging Priya and Sarah
/// sits once, under "Priya Patel, Sarah Lin", between Priya's section and Sarah's.
struct TodoPeopleGroup: Identifiable {
    let names: [String]
    /// One person per name, in `names` order, for the heading's links.
    let people: [Person]
    let todos: [Todo]

    var label: String { names.joined(separator: ", ") }
    var id: String { label }

    /// Keeps the todos' order within each group. Todos tagging nobody are left out. People who
    /// share a name share a section, since its heading couldn't tell them apart.
    static func group(_ todos: [Todo]) -> [TodoPeopleGroup] {
        var order: [[String]] = []
        var byNames: [[String]: [Todo]] = [:]
        for todo in todos {
            let names = names(of: todo)
            guard !names.isEmpty else { continue }
            if byNames[names] == nil { order.append(names) }
            byNames[names, default: []].append(todo)
        }
        return order.sorted { precedes($0, $1) }.map { names in
            let todos = byNames[names] ?? []
            return TodoPeopleGroup(names: names, people: people(named: names, in: todos), todos: todos)
        }
    }

    /// The first person found for each name. People who share a name share a section, so its
    /// link opens one of them.
    private static func people(named names: [String], in todos: [Todo]) -> [Person] {
        let tagged = todos.flatMap(\.people)
        return names.compactMap { name in tagged.first { $0.name == name } }
    }

    /// The names of the people a todo tags, sorted, optionally only those in `ids`.
    static func names(of todo: Todo, among ids: Set<UUID>? = nil) -> [String] {
        todo.people.filter { ids?.contains($0.id) ?? true }.map(\.name).sorted()
    }

    /// Section order: by first name listed, then the next, so ["Priya"] comes before
    /// ["Priya", "Sarah"], which comes before ["Sarah"].
    static func precedes(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.lexicographicallyPrecedes(rhs)
    }

    /// The first and last index a todo can be dragged to in `items`, the list without it: inside
    /// the section it was in at `index`, between the heading above and the next one.
    static func dropRange(at index: Int, in items: [TodoListItem]) -> ClosedRange<Int> {
        let heading = items[..<min(index, items.count)].lastIndex { $0.todoID == nil }
        let next = items[min(index, items.count)...].firstIndex { $0.todoID == nil }
        return ((heading ?? -1) + 1)...(next ?? items.count)
    }
}
