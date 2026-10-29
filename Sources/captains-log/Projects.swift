import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

struct Projects: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage projects",
        subcommands: [List.self, Add.self, Edit.self, Complete.self, Reopen.self, Delete.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List open projects, in the Todos tab's order"
        )

        @Flag(name: .long, help: "Show completed projects instead, most recently completed first")
        var completed: Bool = false

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let descriptor = completed
                ? FetchDescriptor<Project>(
                    predicate: #Predicate { $0.completedDate != nil },
                    sortBy: [SortDescriptor(\.completedDate, order: .reverse)]
                )
                : FetchDescriptor<Project>(
                    predicate: #Predicate { $0.completedDate == nil },
                    sortBy: [SortDescriptor(\.sortOrder)]
                )
            try printJSON(try context.fetch(descriptor).map(ProjectDTO.from), pretty: pretty)
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a project at the bottom of the Todos tab's list"
        )

        @Argument(help: "Project name, unique ignoring case")
        var name: String

        @Option(name: .long, help: "Project notes (markdown), or - to read them from stdin")
        var notes: String?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let notes = try TextInput.resolve([notes])[0]
            let context = ModelContext(try Store.makeContainer())
            let projects = try context.fetch(FetchDescriptor<Project>())
            // Names are #Unique, so inserting a clash would upsert over the existing project.
            let project = Project(name: name)
            guard let validName = ProjectNaming.validated(name, for: project, among: projects) else {
                throw ValidationError(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Project name can't be empty"
                    : "A project named \"\(name)\" already exists")
            }
            project.name = validName
            project.notes = notes
            project.sortOrder = (projects.map(\.sortOrder).max() ?? -1) + 1
            context.insert(project)
            try context.save()

            try printJSON(ProjectDTO.from(project), pretty: pretty)
        }
    }

    struct Edit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Rename a project or change its notes"
        )

        @Argument(help: "Project name or UUID")
        var project: String

        @Option(name: .long, help: "New name, unique ignoring case")
        var name: String?

        @Option(name: .long, help: "Replace the notes (markdown), or - to read them from stdin")
        var notes: String?

        @Flag(name: .long, help: "Remove the notes")
        var clearNotes: Bool = false

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            if notes != nil && clearNotes {
                throw ValidationError("--notes and --clear-notes can't be combined")
            }
            if name == nil && notes == nil && !clearNotes {
                throw ValidationError("Nothing to change; pass --name, --notes or --clear-notes")
            }
        }

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let project = try Projects.project(project, in: context)
            let notes = try TextInput.resolve([notes])[0]
            if let name {
                let projects = try context.fetch(FetchDescriptor<Project>())
                guard let validName = ProjectNaming.validated(name, for: project, among: projects) else {
                    throw ValidationError(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Project name can't be empty"
                        : "A project named \"\(name)\" already exists")
                }
                project.name = validName
            }
            if let notes { project.notes = notes }
            if clearNotes { project.notes = nil }
            try context.save()

            try printJSON(ProjectDTO.from(project), pretty: pretty)
        }
    }

    struct Complete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Complete a project, moving it to Completed",
            discussion: "Completing a project completes its open todos too. The app asks first; here, pass --complete-todos when it has any."
        )

        @Argument(help: "Project name or UUID")
        var project: String

        @Flag(name: .long, help: "Also complete the project's open todos")
        var completeTodos: Bool = false

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let project = try Projects.project(project, in: context)
            guard !project.isCompleted else {
                throw ValidationError("Project is already completed: \(project.name)")
            }
            // Fetched rather than read from project.todos, which can lag behind inserts.
            let projectID = project.id
            let openTodos = try context.fetch(FetchDescriptor<Todo>(
                predicate: #Predicate { $0.completedDate == nil && $0.trashedDate == nil && $0.project?.id == projectID }
            ))
            if !openTodos.isEmpty && !completeTodos {
                throw ValidationError("\(project.name) has \(openTodos.count) open todos; pass --complete-todos to complete them too")
            }
            ProjectCompletion.complete(project, openTodos: openTodos)
            try context.save()

            try printJSON(ProjectDTO.from(project), pretty: pretty)
        }
    }

    struct Reopen: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Reopen a completed project. Its todos stay completed"
        )

        @Argument(help: "Project name or UUID")
        var project: String

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let project = try Projects.project(project, in: context)
            guard project.isCompleted else {
                throw ValidationError("Project is not completed: \(project.name)")
            }
            ProjectCompletion.reopen(project)
            try context.save()

            try printJSON(ProjectDTO.from(project), pretty: pretty)
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a project for good. Its todos, meetings and other records are kept, without a project"
        )

        @Argument(help: "Project name or UUID")
        var project: String

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
            let project = try Projects.project(project, in: context)
            let dto = ProjectDTO.from(project)
            context.delete(project)
            try context.save()

            try printJSON(["deleted": [dto]], pretty: pretty)
        }
    }

    /// Looks a project up by UUID, or else by name, case-insensitively.
    static func project(_ nameOrID: String, in context: ModelContext) throws -> Project {
        if let uuid = UUID(uuidString: nameOrID) {
            guard let project = try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == uuid })).first else {
                throw ValidationError("Project not found: \(nameOrID)")
            }
            return project
        }
        return try Todos.project(named: nameOrID, in: context)
    }
}
