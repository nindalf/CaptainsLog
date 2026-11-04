import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

struct Prune: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List or remove records past the retention set in the app's Settings",
        discussion: """
            Lists what would go; --permanently removes it. Each kind is off until turned on in Settings › Retention: \
            interviews lose their written text (the record, name, level and decision stay), calendar events with no \
            written meeting or interview are deleted, and PRs are deleted by their last update on GitHub. The app \
            does the same every hour.
            """
    )

    @Flag(name: .long, help: "Remove the records instead of listing them")
    var permanently: Bool = false

    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false

    mutating func run() async throws {
        let settings = AppSettings().retention
        let context = ModelContext(try Store.makeContainer())
        let expired = try ExpiredRecords.find(settings, in: context)
        let output = PruneDTO(
            removed: permanently,
            retentionDays: RetentionDaysDTO(settings),
            interviews: expired.interviews.map(InterviewDTO.from),
            calendarEvents: expired.calendarEvents.map(CalendarEventDTO.from),
            pullRequests: expired.pullRequests.map(PullRequestDTO.from)
        )
        if permanently { try expired.remove(in: context) }
        try printJSON(output, pretty: pretty)
    }

    struct PruneDTO: Encodable {
        let removed: Bool
        let retentionDays: RetentionDaysDTO
        let interviews: [InterviewDTO]
        let calendarEvents: [CalendarEventDTO]
        let pullRequests: [PullRequestDTO]
    }

    /// Null for a kind that is off.
    struct RetentionDaysDTO: Encodable {
        let interviews: Int?
        let calendarEvents: Int?
        let pullRequests: Int?

        init(_ settings: RetentionSettings) {
            func days(_ rule: RetentionRule) -> Int? { rule.isEnabled ? rule.days : nil }
            interviews = days(settings.interviews)
            calendarEvents = days(settings.calendarEvents)
            pullRequests = days(settings.pullRequests)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(interviews, forKey: .interviews)
            try container.encode(calendarEvents, forKey: .calendarEvents)
            try container.encode(pullRequests, forKey: .pullRequests)
        }

        enum CodingKeys: String, CodingKey { case interviews, calendarEvents, pullRequests }
    }
}
