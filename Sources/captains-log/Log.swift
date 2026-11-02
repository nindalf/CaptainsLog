import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

struct Log: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage log entries",
        subcommands: [List.self, Add.self, Edit.self, Delete.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List log entries, newest first"
        )

        @Option(name: .long, help: "Start date (ISO 8601, e.g. 2026-04-28). Defaults to a week ago")
        var from: String?

        @Option(name: .long, help: "End date, inclusive (ISO 8601, e.g. 2026-05-02)")
        var to: String?

        @Option(name: .long, help: "Only entries with this tag")
        var tag: String?

        @Option(name: .long, help: "Only entries from this source: manual, slack, linear")
        var source: String?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let source = try source.map { raw in
                guard let s = EntrySource(rawValue: raw) else {
                    throw ValidationError("Invalid source '\(raw)'. Use: manual, slack, linear")
                }
                return s
            }
            let range = try CLIDate.range(from: from, to: to, defaultFrom: CLIDate.weekAgo, defaultTo: .distantFuture)
            let start = range.lowerBound
            let end = range.upperBound

            let context = ModelContext(try Store.makeContainer())
            let descriptor = FetchDescriptor<LogEntry>(
                predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            var entries = try context.fetch(descriptor)

            // SwiftData predicates can't filter on enum or array properties (hence PullRequest.stateRawValue).
            if let source {
                entries = entries.filter { $0.source == source }
            }
            if let tag {
                entries = entries.filter { $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
            }

            try printJSON(entries.map(LogEntryDTO.listed), pretty: pretty)
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a new log entry",
            discussion: "Pass - as the content to read it from stdin."
        )

        @Argument(help: "Entry title")
        var title: String

        @Option(name: .shortAndLong, help: "Entry content (markdown)")
        var content: String = ""

        @Option(name: .long, help: "Entry source: manual, slack, linear")
        var source: String = "manual"

        @Flag(name: .customLong("private"), help: "Make it private, to keep it out of anything shared")
        var isPrivate: Bool = false

        @Option(name: .shortAndLong, help: "Comma-separated tags")
        var tags: String?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            guard let src = EntrySource(rawValue: source) else {
                throw ValidationError("Invalid source '\(source)'. Use: manual, slack, linear")
            }

            let parsedTags = tags?.split(separator: ",").map {
                String($0.trimmingCharacters(in: .whitespaces))
            } ?? []

            let content = try TextInput.resolve([content])[0] ?? ""
            let container = try Store.makeContainer()
            let context = ModelContext(container)
            let entry = LogEntry(
                timestamp: .now,
                source: src,
                title: title,
                content: content,
                isPrivate: isPrivate
            )
            entry.tags = parsedTags
            context.insert(entry)
            try entry.linkMentionedPeople(in: context)
            try context.save()

            try printJSON(LogEntryDTO.from(entry), pretty: pretty)
        }
    }

    struct Edit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Change a log entry's title, content, tags, source, or privacy",
            discussion: "Pass - as the content to read it from stdin."
        )

        @Argument(help: "Log entry UUID")
        var id: String

        @Option(name: .long, help: "New title")
        var title: String?

        @Option(name: .shortAndLong, help: "Replace the content (markdown)")
        var content: String?

        @Option(name: .shortAndLong, help: "Replace the tags, comma-separated. Empty removes them all")
        var tags: String?

        @Option(name: .long, help: "Source: manual, slack, linear")
        var source: String?

        @Flag(name: .customLong("private"), inversion: .prefixedNo, help: "Make it private, or not, as the app's lock does")
        var isPrivate: Bool?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError("Title can't be empty")
            }
            if let source, EntrySource(rawValue: source) == nil {
                throw ValidationError("Invalid source '\(source)'. Use: manual, slack, linear")
            }
            let changes: [Bool] = [title != nil, content != nil, tags != nil, source != nil, isPrivate != nil]
            if !changes.contains(true) {
                throw ValidationError("Nothing to change")
            }
        }

        mutating func run() async throws {
            let content = try TextInput.resolve([content])[0]
            let context = ModelContext(try Store.makeContainer())
            let entry = try Log.entry(id: id, in: context)

            if let title { entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let content { entry.content = content }
            if let tags {
                entry.tags = tags.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
            if let source { entry.source = EntrySource(rawValue: source)! }
            if let isPrivate { entry.isPrivate = isPrivate }
            if title != nil || content != nil { try entry.linkMentionedPeople(in: context) }
            try context.save()

            try printJSON(LogEntryDTO.from(entry), pretty: pretty)
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a log entry for good. This can't be undone",
            discussion: "Log entries have no Trash; the app asks before deleting one."
        )

        @Argument(help: "Log entry UUID")
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
            let entry = try Log.entry(id: id, in: context)
            let dto = LogEntryDTO.from(entry)
            context.delete(entry)
            try context.save()

            try printJSON(["deleted": [dto]], pretty: pretty)
        }
    }

    static func entry(id: String, in context: ModelContext) throws -> LogEntry {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("Invalid UUID: \(id)")
        }
        guard let entry = try context.fetch(FetchDescriptor<LogEntry>(predicate: #Predicate { $0.id == uuid })).first else {
            throw ValidationError("Log entry not found: \(id)")
        }
        return entry
    }
}
