import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

struct Show: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print records in full, whatever their type",
        discussion: "Looks the id up in every record type. The output's \"type\" field says which it was."
    )

    @Argument(help: "Record UUIDs, from any list or search. More than one prints a list")
    var ids: [String]

    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false

    mutating func run() async throws {
        let uuids = try ids.map { id in
            guard let uuid = UUID(uuidString: id) else { throw ValidationError("Invalid UUID: \(id)") }
            return uuid
        }
        let context = ModelContext(try Store.makeContainer())
        let records = try uuids.map { try Self.record($0, in: context) }
        if records.count == 1 {
            try printJSON(records[0], pretty: pretty)
        } else {
            try printJSON(records, pretty: pretty)
        }
    }

    private static func record(_ uuid: UUID, in context: ModelContext) throws -> AnyEncodable {
        if let e = try context.fetch(FetchDescriptor<LogEntry>(predicate: #Predicate { $0.id == uuid })).first {
            return AnyEncodable(value: LogEntryDetail.from(e))
        }
        if let m = try context.fetch(FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == uuid })).first {
            return AnyEncodable(value: try MeetingDetail.load(m, in: context))
        }
        if let i = try context.fetch(FetchDescriptor<Interview>(predicate: #Predicate { $0.id == uuid })).first {
            let todos = try context.fetch(FetchDescriptor<Todo>(
                predicate: #Predicate { $0.trashedDate == nil && $0.interview?.id == uuid },
                sortBy: [SortDescriptor(\.sortOrder)]
            ))
            return AnyEncodable(value: InterviewDetail.from(i, todos: todos))
        }
        if let pr = try context.fetch(FetchDescriptor<PullRequest>(predicate: #Predicate { $0.id == uuid })).first {
            let todos = try context.fetch(FetchDescriptor<Todo>(
                predicate: #Predicate { $0.trashedDate == nil && $0.pullRequest?.id == uuid },
                sortBy: [SortDescriptor(\.sortOrder)]
            ))
            return AnyEncodable(value: PullRequestDetail.from(pr, todos: todos))
        }
        if let t = try context.fetch(FetchDescriptor<Todo>(predicate: #Predicate { $0.id == uuid })).first {
            return AnyEncodable(value: TodoDetail.from(t))
        }
        if let p = try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == uuid })).first {
            return AnyEncodable(value: ProjectDetail.from(p))
        }
        if let p = try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == uuid })).first {
            return AnyEncodable(value: PersonDetail.from(p))
        }
        if let f = try context.fetch(FetchDescriptor<Feedback>(predicate: #Predicate { $0.id == uuid })).first {
            return AnyEncodable(value: FeedbackDetail.from(f))
        }
        if let e = try context.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.id == uuid })).first {
            return AnyEncodable(value: CalendarEventDetail.from(e))
        }
        throw ValidationError("No record with id \(uuid.uuidString)")
    }
}
