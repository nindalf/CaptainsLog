import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

struct Show: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print one record in full, whatever its type",
        discussion: "Looks the id up in every record type. The output's \"type\" field says which it was."
    )

    @Argument(help: "Record UUID, from any list or search")
    var id: String

    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false

    mutating func run() async throws {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("Invalid UUID: \(id)")
        }
        let context = ModelContext(try Store.makeContainer())

        if let e = try context.fetch(FetchDescriptor<LogEntry>(predicate: #Predicate { $0.id == uuid })).first {
            return try printJSON(LogEntryDetail.from(e), pretty: pretty)
        }
        if let m = try context.fetch(FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == uuid })).first {
            return try printJSON(MeetingDetail.load(m, in: context), pretty: pretty)
        }
        if let i = try context.fetch(FetchDescriptor<Interview>(predicate: #Predicate { $0.id == uuid })).first {
            let todos = try context.fetch(FetchDescriptor<Todo>(
                predicate: #Predicate { $0.trashedDate == nil && $0.interview?.id == uuid },
                sortBy: [SortDescriptor(\.sortOrder)]
            ))
            return try printJSON(InterviewDetail.from(i, todos: todos), pretty: pretty)
        }
        if let pr = try context.fetch(FetchDescriptor<PullRequest>(predicate: #Predicate { $0.id == uuid })).first {
            let todos = try context.fetch(FetchDescriptor<Todo>(
                predicate: #Predicate { $0.trashedDate == nil && $0.pullRequest?.id == uuid },
                sortBy: [SortDescriptor(\.sortOrder)]
            ))
            return try printJSON(PullRequestDetail.from(pr, todos: todos), pretty: pretty)
        }
        if let t = try context.fetch(FetchDescriptor<Todo>(predicate: #Predicate { $0.id == uuid })).first {
            return try printJSON(TodoDetail.from(t), pretty: pretty)
        }
        if let p = try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == uuid })).first {
            return try printJSON(ProjectDetail.from(p), pretty: pretty)
        }
        if let p = try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == uuid })).first {
            return try printJSON(PersonDetail.from(p), pretty: pretty)
        }
        if let f = try context.fetch(FetchDescriptor<Feedback>(predicate: #Predicate { $0.id == uuid })).first {
            return try printJSON(FeedbackDetail.from(f), pretty: pretty)
        }
        if let e = try context.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.id == uuid })).first {
            return try printJSON(CalendarEventDetail.from(e), pretty: pretty)
        }
        throw ValidationError("No record with id \(id)")
    }
}
