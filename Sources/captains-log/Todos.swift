import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

extension SmartList: ExpressibleByArgument {}

struct Todos: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage todos",
        subcommands: [List.self, Add.self, Edit.self, Complete.self, Reopen.self, Trash.self, Restore.self, Delete.self, EmptyTrash.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List todos"
        )

        @Flag(name: .long, help: "Show completed todos instead of open ones (same as --list logbook)")
        var completed: Bool = false

        @Flag(name: .long, help: "Show only overdue todos")
        var overdue: Bool = false

        @Option(name: .long, help: "Show one smart list")
        var list: SmartList?

        @Option(name: .long, help: "Show only todos in this project")
        var project: String?

        @Option(name: .long, help: "Show only todos tagging this person (UUID or name). Repeat to match any of several")
        var person: [String] = []

        @Option(name: .long, help: "With --completed: completed on or after this day (ISO 8601, e.g. 2026-04-28)")
        var from: String?

        @Option(name: .long, help: "With --completed: completed on or before this day, inclusive")
        var to: String?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            if (from != nil || to != nil) && !completed && list != .logbook {
                throw ValidationError("--from and --to filter by completion date; pass --completed")
            }
            if completed && list != nil {
                throw ValidationError("--completed and --list can't be combined; use --list logbook")
            }
        }

        mutating func run() async throws {
            let container = try Store.makeContainer()
            let context = ModelContext(container)
            let projectID = try project.map { try Todos.project(named: $0, in: context).id }

            let descriptor: FetchDescriptor<Todo>
            switch list ?? (completed ? .logbook : nil) {
            case .trash:
                descriptor = FetchDescriptor<Todo>(
                    predicate: #Predicate { $0.trashedDate != nil },
                    sortBy: [SortDescriptor(\.trashedDate, order: .reverse)]
                )
            case .logbook:
                descriptor = FetchDescriptor<Todo>(
                    predicate: #Predicate { $0.completedDate != nil && $0.trashedDate == nil },
                    sortBy: [SortDescriptor(\.completedDate, order: .reverse)]
                )
            case .upcoming:
                descriptor = FetchDescriptor<Todo>(
                    predicate: #Predicate { $0.completedDate == nil && $0.trashedDate == nil },
                    sortBy: [SortDescriptor(\.dueDate), SortDescriptor(\.sortOrder)]
                )
            default:
                descriptor = FetchDescriptor<Todo>(
                    predicate: #Predicate { $0.completedDate == nil && $0.trashedDate == nil },
                    sortBy: [SortDescriptor(\.sortOrder)]
                )
            }

            var todos = try context.fetch(descriptor)

            // SmartList depends on today's date, which a predicate can't express.
            if let list {
                let now = Date.now
                todos = todos.filter { list.contains($0, now: now) }
            }
            if let projectID {
                todos = todos.filter { $0.project?.id == projectID }
            }
            if !person.isEmpty {
                let ids = Set(person.compactMap(UUID.init(uuidString:)))
                let names = person.filter { UUID(uuidString: $0) == nil }
                todos = todos.filter { todo in
                    todo.people.contains { p in
                        ids.contains(p.id) || names.contains { p.name.localizedCaseInsensitiveContains($0) }
                    }
                }
            }
            if from != nil || to != nil {
                let range = try CLIDate.range(from: from, to: to, defaultFrom: .distantPast, defaultTo: .distantFuture)
                todos = todos.filter { $0.completedDate.map(range.contains) ?? false }
            }
            if overdue {
                let now = Date.now
                todos = todos.filter { t in
                    guard let due = t.dueDate else { return false }
                    return due < now && !t.isCompleted
                }
            }

            try printJSON(todos.map(TodoDTO.from), pretty: pretty)
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a new todo"
        )

        @Argument(help: "Todo title")
        var title: String

        @Option(name: .long, help: "Due date (ISO 8601, e.g. 2026-05-05)")
        var dueDate: String?

        @Flag(name: .long, help: "Park it in Someday")
        var someday: Bool = false

        @Option(name: .long, help: "Add it to this existing project (it then shows in Anytime)")
        var project: String?

        @Option(name: .long, help: "Notes (markdown), or - to read them from stdin")
        var notes: String?

        @Flag(name: .customLong("private"), help: "Make it private, to keep it out of anything shared")
        var isPrivate: Bool = false

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            if dueDate != nil && someday {
                throw ValidationError("--due-date and --someday can't be combined")
            }
        }

        mutating func run() async throws {
            let due = try dueDate.map(CLIDate.day)
            let notes = try TextInput.resolve([notes])[0]

            let container = try Store.makeContainer()
            let context = ModelContext(container)
            let project = try project.map { try Todos.project(named: $0, in: context) }

            let todo = Todo(title: title)
            todo.notes = notes
            todo.isPrivate = isPrivate
            if let due {
                todo.schedule(on: due)
            } else {
                todo.setUndated(someday ? .someday : .inbox)
            }
            let open = try context.fetch(FetchDescriptor<Todo>(predicate: #Predicate { $0.completedDate == nil }))
            todo.sortOrder = TodoOrdering.topSortOrder(among: open)
            context.insert(todo)
            todo.project = project
            try todo.linkMentionedPeople(in: context)
            try context.save()

            try printJSON(TodoDTO.from(todo), pretty: pretty)
        }
    }

    struct Edit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Change a todo's title, notes, When, project or privacy"
        )

        @Argument(help: "Todo UUID")
        var id: String

        @Option(name: .long, help: "New title")
        var title: String?

        @Option(name: .long, help: "Replace the notes (markdown), or - to read them from stdin")
        var notes: String?

        @Flag(name: .long, help: "Remove the notes")
        var clearNotes: Bool = false

        @Option(name: .long, help: "Schedule it for this day (ISO 8601, e.g. 2026-05-05)")
        var dueDate: String?

        @Flag(name: .long, help: "Move it to Someday")
        var someday: Bool = false

        @Flag(name: .long, help: "Clear its When, back to the Inbox or Anytime")
        var clearWhen: Bool = false

        @Option(name: .long, help: "Move it into this existing project")
        var project: String?

        @Flag(name: .long, help: "Take it out of its project")
        var noProject: Bool = false

        @Flag(name: .customLong("private"), inversion: .prefixedNo, help: "Make it private, or not, as the app's lock does")
        var isPrivate: Bool?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            if [dueDate != nil, someday, clearWhen].filter({ $0 }).count > 1 {
                throw ValidationError("Pass only one of --due-date, --someday and --clear-when")
            }
            if project != nil && noProject {
                throw ValidationError("--project and --no-project can't be combined")
            }
            if notes != nil && clearNotes {
                throw ValidationError("--notes and --clear-notes can't be combined")
            }
            if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError("Title can't be empty")
            }
            let changes: [Bool] = [title != nil, notes != nil, clearNotes, dueDate != nil, someday, clearWhen, project != nil, noProject, isPrivate != nil]
            if !changes.contains(true) {
                throw ValidationError("Nothing to change")
            }
        }

        mutating func run() async throws {
            let notes = try TextInput.resolve([notes])[0]
            let when: TodoWhen? = try dueDate.map { .day(try CLIDate.day($0)) }
                ?? (someday ? .someday : clearWhen ? .unset : nil)

            let context = ModelContext(try Store.makeContainer())
            let todo = try Todos.todo(id: id, in: context)
            let newProject = try project.map { try Todos.project(named: $0, in: context) }

            if let title { todo.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let notes { todo.notes = notes }
            if clearNotes { todo.notes = nil }
            when?.apply(to: todo)
            if let newProject { todo.project = newProject }
            if noProject { todo.project = nil }
            if let isPrivate { todo.isPrivate = isPrivate }
            if title != nil || notes != nil || clearNotes { try todo.linkMentionedPeople(in: context) }
            try context.save()

            try printJSON(TodoDTO.from(todo), pretty: pretty)
        }
    }

    struct Complete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Mark a todo as completed"
        )

        @Argument(help: "Todo UUID")
        var id: String

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let todo = try Todos.todo(id: id, in: context)
            todo.completedDate = .now
            try context.save()

            try printJSON(TodoDTO.from(todo), pretty: pretty)
        }
    }

    struct Reopen: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Reopen a completed todo"
        )

        @Argument(help: "Todo UUID")
        var id: String

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let todo = try Todos.todo(id: id, in: context)
            guard todo.isCompleted else {
                throw ValidationError("Todo is not completed: \(id)")
            }
            todo.reopen()
            try context.save()

            try printJSON(TodoDTO.from(todo), pretty: pretty)
        }
    }

    struct Trash: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Move a todo to the Trash"
        )

        @Argument(help: "Todo UUID")
        var id: String

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let todo = try Todos.todo(id: id, in: context)
            if !todo.isTrashed {
                todo.moveToTrash()
                try context.save()
            }

            try printJSON(TodoDTO.from(todo), pretty: pretty)
        }
    }

    struct Restore: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Restore a todo from the Trash"
        )

        @Argument(help: "Todo UUID")
        var id: String

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let todo = try Todos.todo(id: id, in: context)
            guard todo.isTrashed else {
                throw ValidationError("Todo is not in the Trash: \(id)")
            }
            todo.restoreFromTrash()
            try context.save()

            try printJSON(TodoDTO.from(todo), pretty: pretty)
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a todo in the Trash for good. This can't be undone",
            discussion: "Only todos already in the Trash can be deleted, as in the app. Move one there with trash first."
        )

        @Argument(help: "Todo UUID")
        var id: String

        @Flag(name: .long, help: "Required: confirms the delete is permanent")
        var permanently: Bool = false

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            guard permanently else {
                throw ValidationError("Deleting is permanent; pass --permanently to confirm")
            }
        }

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let todo = try Todos.todo(id: id, in: context)
            guard todo.isTrashed else {
                throw ValidationError("Todo is not in the Trash: \(id). Move it there with trash first")
            }
            let dto = TodoDTO.from(todo)
            context.delete(todo)
            try context.save()

            try printJSON(["deleted": [dto]], pretty: pretty)
        }
    }

    struct EmptyTrash: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "empty-trash",
            abstract: "Delete every todo in the Trash for good. This can't be undone"
        )

        @Flag(name: .long, help: "Required: confirms the delete is permanent")
        var permanently: Bool = false

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            guard permanently else {
                throw ValidationError("Emptying the Trash is permanent; pass --permanently to confirm")
            }
        }

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let trashed = try context.fetch(FetchDescriptor<Todo>(predicate: #Predicate { $0.trashedDate != nil }))
            let dtos = trashed.map(TodoDTO.from)
            trashed.forEach(context.delete)
            try context.save()

            try printJSON(["deleted": dtos], pretty: pretty)
        }
    }

    static func todo(id: String, in context: ModelContext) throws -> Todo {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("Invalid UUID: \(id)")
        }
        let descriptor = FetchDescriptor<Todo>(predicate: #Predicate { $0.id == uuid })
        guard let todo = try context.fetch(descriptor).first else {
            throw ValidationError("Todo not found: \(id)")
        }
        return todo
    }

    /// Looks a project up by name, case-insensitively. Never creates one: names are `#Unique`, so
    /// inserting a project can upsert over an existing one.
    static func project(named name: String, in context: ModelContext) throws -> Project {
        let projects = try context.fetch(FetchDescriptor<Project>())
        guard let project = projects.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw ValidationError("No project named \"\(name)\"")
        }
        return project
    }
}
