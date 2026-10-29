import Foundation
import CaptainsLogKit

/// Anytime and Someday as Things lays them out: todos without a project first, under no heading,
/// then one group per project in the column's project order.
struct TodoProjectGroup: Identifiable {
    let project: Project?
    let todos: [Todo]

    var id: UUID? { project?.id }

    /// Keeps the todos' order within each group.
    static func group(_ todos: [Todo]) -> [TodoProjectGroup] {
        let loose = todos.filter { $0.project == nil }
        let byProject = Dictionary(grouping: todos.filter { $0.project != nil }) { $0.project!.id }
        let projects = byProject.values.compactMap(\.first?.project).sorted {
            ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name)
        }
        let groups = projects.map { TodoProjectGroup(project: $0, todos: byProject[$0.id] ?? []) }
        return (loose.isEmpty ? [] : [TodoProjectGroup(project: nil, todos: loose)]) + groups
    }
}

/// One entry in a reorderable list: a todo row, a project heading in the grouped lists, or a
/// date heading in Upcoming (by its label).
enum TodoListItem: Hashable {
    case todo(UUID)
    case heading(UUID)
    case group(String)

    var todoID: UUID? {
        if case .todo(let id) = self { id } else { nil }
    }

    /// The project heading above `id`, which is the project a todo dropped there joins.
    static func projectID(above id: UUID, in items: [TodoListItem]) -> UUID? {
        var project: UUID?
        for item in items {
            switch item {
            case .heading(let headingID): project = headingID
            case .todo(let todoID) where todoID == id: return project
            case .todo, .group: break
            }
        }
        return nil
    }
}
