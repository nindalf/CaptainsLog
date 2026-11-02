import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

enum FeedType: String, CaseIterable, ExpressibleByArgument {
    case log, meeting, interview, pr, todo
}

struct FeedCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "feed",
        abstract: "Everything the Log tab's feed shows in a date range, newest first",
        discussion: "Log entries, meetings with notes, interviews with notes, my PRs (dated by merge) and completed todos. Use show <id> for full text."
    )

    @Option(name: .long, help: "Start date (ISO 8601, e.g. 2026-04-28). Defaults to a week ago")
    var from: String?

    @Option(name: .long, help: "End date, inclusive (ISO 8601, e.g. 2026-05-02)")
    var to: String?

    @Option(name: .long, help: "Only this type: log, meeting, interview, pr, todo. Repeatable")
    var type: [FeedType] = []

    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false

    mutating func run() async throws {
        let range = try CLIDate.range(from: from, to: to, defaultFrom: CLIDate.weekAgo, defaultTo: .distantFuture)
        let start = range.lowerBound
        let end = range.upperBound
        let types = type.isEmpty ? Set(FeedType.allCases) : Set(type)
        let context = ModelContext(try Store.makeContainer())
        var items: [FeedItemDTO] = []

        if types.contains(.log) {
            let entries = try context.fetch(FetchDescriptor<LogEntry>(
                predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end }
            ))
            items += entries.map {
                FeedItemDTO(type: .log, id: $0.id, date: $0.timestamp, title: $0.title, isPrivate: $0.isPrivate,
                            project: $0.project, tags: $0.tags, snippet: $0.content)
            }
        }
        if types.contains(.meeting) {
            let meetings = try context.fetch(FetchDescriptor<Meeting>(
                predicate: #Predicate { $0.date >= start && $0.date < end }
            ))
            items += meetings.filter(Feed.includes).map {
                FeedItemDTO(type: .meeting, id: $0.id, date: $0.date, title: $0.title, isPrivate: $0.isPrivate,
                            project: $0.project, tags: $0.tags, snippet: $0.summary ?? $0.notes)
            }
        }
        if types.contains(.interview) {
            let interviews = try context.fetch(FetchDescriptor<Interview>(
                predicate: #Predicate { $0.date >= start && $0.date < end }
            ))
            items += interviews.filter(Feed.includes).map {
                FeedItemDTO(type: .interview, id: $0.id, date: $0.date, title: $0.candidateName, isPrivate: $0.isPrivate,
                            project: nil, tags: [], snippet: $0.conclusion ?? $0.rawNotes)
            }
        }
        if types.contains(.pr) {
            // Filed under the merge date, which a predicate can't express; every PR in range was created before its end.
            let prs = try context.fetch(FetchDescriptor<PullRequest>(
                predicate: #Predicate { $0.isAuthoredByMe && $0.createdAt < end }
            ))
            items += prs.filter { Feed.includes($0) && range.contains(Feed.date(of: $0)) }.map {
                FeedItemDTO(type: .pr, id: $0.id, date: Feed.date(of: $0), title: "\($0.repo)#\($0.number) \($0.title)",
                            isPrivate: nil, project: $0.project, tags: $0.tags, snippet: $0.body)
            }
        }
        if types.contains(.todo) {
            let todos = try context.fetch(FetchDescriptor<Todo>(
                predicate: #Predicate {
                    $0.completedDate != nil && $0.trashedDate == nil
                        && $0.completedDate.flatMap { $0 >= start && $0 < end } == true
                }
            ))
            items += todos.filter(Feed.includes).map {
                FeedItemDTO(type: .todo, id: $0.id, date: Feed.date(of: $0), title: $0.title, isPrivate: $0.isPrivate,
                            project: $0.project, tags: [], snippet: $0.notes)
            }
        }

        try printJSON(items.sorted { $0.date > $1.date }, pretty: pretty)
    }
}

struct FeedItemDTO: Encodable {
    let type: String
    let id: UUID
    let date: Date
    let title: String
    let isPrivate: Bool?
    let project: String?
    let tags: [String]
    /// The start of the record's main text: log content, a meeting's summary or notes, an
    /// interview's conclusion or notes, a PR's body, a todo's notes.
    let snippet: String?

    init(type: FeedType, id: UUID, date: Date, title: String, isPrivate: Bool?, project: Project?, tags: [String], snippet: String?) {
        self.type = type.rawValue
        self.id = id
        self.date = date
        self.title = title
        self.isPrivate = isPrivate
        self.project = project?.name
        self.tags = tags
        // A private record's text is left to `show`.
        self.snippet = isPrivate == true ? nil : snippet.flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
    }
}
