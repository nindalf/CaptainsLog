import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

struct Prune: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List or remove records past the retention set in the app's Settings",
        discussion: """
            Lists what would go; --permanently removes it. Each kind is on until turned off in Settings › Retention: \
            interviews with no open todo are deleted with their calendar event and todos, meetings (notes included) \
            and calendar events without an interview are deleted, and PRs are deleted by their last update on \
            GitHub. The app does the same every hour.
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
        let interviews = expired.interviews.filter { outsideInvitations.shows($0) }
        let meetings = expired.meetings.filter { outsideInvitations.shows($0) }
        let events = expired.calendarEvents.filter { outsideInvitations.shows($0) }
        let listed = interviews.count + meetings.count + events.count
        let withheld = expired.interviews.count + expired.meetings.count + expired.calendarEvents.count - listed
        let output = PruneDTO(
            removed: permanently,
            retentionDays: RetentionDaysDTO(settings),
            interviews: interviews.map(InterviewDTO.from),
            meetings: meetings.map(MeetingDTO.from),
            calendarEvents: events.map(CalendarEventDTO.from),
            pullRequests: expired.pullRequests.map(PullRequestDTO.from),
            withheld: withheld == 0 ? nil : withheld
        )
        if permanently { try expired.remove(in: context) }
        try printJSON(output, pretty: pretty)
    }

    struct PruneDTO: Encodable {
        let removed: Bool
        let retentionDays: RetentionDaysDTO
        let interviews: [InterviewDTO]
        let meetings: [MeetingDTO]
        let calendarEvents: [CalendarEventDTO]
        let pullRequests: [PullRequestDTO]
        /// Records from outside invitations, left out of the lists above but removed with them all the same.
        let withheld: Int?
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
