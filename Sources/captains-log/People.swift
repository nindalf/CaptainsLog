import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

struct People: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage people",
        subcommands: [List.self, Edit.self, Merge.self, Import.self, Export.self, FeedbackCommands.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List people as the People tab does: meaningful contacts, most active first"
        )

        @Flag(name: .long, help: "Include people who are only calendar attendees")
        var all: Bool = false

        @Option(name: .long, help: "Only people whose name, email or handles contain this")
        var search: String?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let query = search?.trimmingCharacters(in: .whitespaces)
            let people = try context.fetch(FetchDescriptor<Person>())
                .filter { person in
                    guard all || person.isMeaningfulContact else { return false }
                    guard let query, !query.isEmpty else { return true }
                    return [person.name, person.email, person.githubHandle, person.slackHandle]
                        .contains { $0?.localizedCaseInsensitiveContains(query) ?? false }
                }
                .sorted { lhs, rhs in
                    if lhs.activityScore != rhs.activityScore {
                        return lhs.activityScore > rhs.activityScore
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            try printJSON(people.map(PersonDTO.from), pretty: pretty)
        }
    }

    struct Edit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Change a person's name, email or handles",
            discussion: "An empty value clears an email or handle."
        )

        @Argument(help: "Person UUID")
        var id: String

        @Option(name: .long, help: "New name")
        var name: String?

        @Option(name: .long, help: "Email")
        var email: String?

        @Option(name: .long, help: "GitHub handle")
        var github: String?

        @Option(name: .long, help: "Slack handle")
        var slack: String?

        @Flag(inversion: .prefixedNo, help: "Sync every PR they author in the configured repos, not just review requests. Needs a GitHub handle")
        var syncPrs: Bool?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError("Name can't be empty")
            }
            if [name, email, github, slack].allSatisfy({ $0 == nil }) && syncPrs == nil {
                throw ValidationError("Nothing to change")
            }
        }

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let person = try People.person(id: id, in: context)
            if let name { person.name = name }
            if let email { person.email = email }
            if let github { person.githubHandle = github }
            if let slack { person.slackHandle = slack }
            person.trimWhitespace()
            if let syncPrs {
                if syncPrs && person.githubHandle == nil {
                    throw ValidationError("\(person.name) has no GitHub handle. Set one with --github")
                }
                person.syncsPullRequests = syncPrs
            }
            try context.save()

            try printJSON(PersonDTO.from(person), pretty: pretty)
        }
    }

    struct Merge: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Fold a duplicate person into another, then delete the duplicate",
            discussion: "Moves every meeting, PR, feedback item, todo and interview onto the person kept and fills their empty email and handles (Person.absorb). The duplicate can't be brought back."
        )

        @Argument(help: "UUID of the person to keep")
        var keep: String

        @Argument(help: "UUID of the duplicate to fold in and delete")
        var duplicate: String

        @Flag(name: .long, help: "Required: confirms the duplicate is deleted")
        var yes: Bool = false

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            guard yes else {
                throw ValidationError("Merging deletes the duplicate; pass --yes to confirm")
            }
        }

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let person = try People.person(id: keep, in: context)
            let other = try People.person(id: duplicate, in: context)
            guard person.id != other.id else {
                throw ValidationError("Can't merge a person into themselves")
            }
            person.absorb(other, in: context)
            try context.save()

            try printJSON(PersonDetail.from(person), pretty: pretty)
        }
    }


    struct FeedbackCommands: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "feedback",
            abstract: "Add, edit and delete feedback a person received. Feedback to you goes on your own page",
            discussion: "Also shown in full by show <person id>.",
            subcommands: [List.self, Add.self, Edit.self, Delete.self]
        )

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List feedback in a date range, newest first"
            )

            @Option(name: .long, help: "Start date (ISO 8601, e.g. 2026-04-28). Defaults to a week ago")
            var from: String?

            @Option(name: .long, help: "End date, inclusive (ISO 8601, e.g. 2026-05-02)")
            var to: String?

            @Option(name: .long, help: "Only feedback for this person (UUID)")
            var person: String?

            @Flag(name: .long, help: "Pretty-print JSON output")
            var pretty: Bool = false

            mutating func run() async throws {
                let range = try CLIDate.range(from: from, to: to, defaultFrom: CLIDate.weekAgo, defaultTo: .distantFuture)
                let start = range.lowerBound
                let end = range.upperBound
                let context = ModelContext(try Store.makeContainer())
                let personID = try person.map { try People.person(id: $0, in: context).id }
                var items = try context.fetch(FetchDescriptor<Feedback>(
                    predicate: #Predicate { $0.date >= start && $0.date < end },
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                ))
                if let personID { items = items.filter { $0.person.id == personID } }

                try printJSON(items.map(FeedbackDetail.from), pretty: pretty)
            }
        }

        struct Add: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Add feedback for a person"
            )

            @Argument(help: "Person UUID")
            var person: String

            @Argument(help: "The feedback (markdown), or - to read it from stdin")
            var content: String

            @Option(name: .long, help: "Date (ISO 8601, e.g. 2026-05-05). Defaults to now")
            var date: String?

            @Flag(name: .long, help: "Pretty-print JSON output")
            var pretty: Bool = false

            mutating func run() async throws {
                let content = try TextInput.resolve([content])[0] ?? ""
                let date = try date.map(CLIDate.day) ?? .now
                let context = ModelContext(try Store.makeContainer())
                let person = try People.person(id: self.person, in: context)
                let item = Feedback(date: date, person: person, content: content)
                context.insert(item)
                try context.save()

                try printJSON(FeedbackDetail.from(item), pretty: pretty)
            }
        }

        struct Edit: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Change a feedback item's content or date"
            )

            @Argument(help: "Feedback UUID")
            var id: String

            @Option(name: .long, help: "Replace the content (markdown), or - to read it from stdin")
            var content: String?

            @Option(name: .long, help: "Date (ISO 8601, e.g. 2026-05-05)")
            var date: String?

            @Flag(name: .long, help: "Pretty-print JSON output")
            var pretty: Bool = false

            func validate() throws {
                if content == nil && date == nil {
                    throw ValidationError("Nothing to change")
                }
            }

            mutating func run() async throws {
                let content = try TextInput.resolve([content])[0]
                let date = try date.map(CLIDate.day)
                let context = ModelContext(try Store.makeContainer())
                let item = try FeedbackCommands.feedback(id: id, in: context)
                if let content { item.content = content }
                if let date { item.date = date }
                try context.save()

                try printJSON(FeedbackDetail.from(item), pretty: pretty)
            }
        }

        struct Delete: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Delete a feedback item for good. This can't be undone"
            )

            @Argument(help: "Feedback UUID")
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
                let item = try FeedbackCommands.feedback(id: id, in: context)
                let dto = FeedbackDetail.from(item)
                context.delete(item)
                try context.save()

                try printJSON(["deleted": [dto]], pretty: pretty)
            }
        }

        static func feedback(id: String, in context: ModelContext) throws -> Feedback {
            guard let uuid = UUID(uuidString: id) else {
                throw ValidationError("Invalid UUID: \(id)")
            }
            guard let item = try context.fetch(FetchDescriptor<Feedback>(predicate: #Predicate { $0.id == uuid })).first else {
                throw ValidationError("Feedback not found: \(id)")
            }
            return item
        }
    }

    static func person(id: String, in context: ModelContext) throws -> Person {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("Invalid UUID: \(id)")
        }
        guard let person = try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == uuid })).first else {
            throw ValidationError("Person not found: \(id)")
        }
        return person
    }
}
