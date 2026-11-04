import CaptainsLogKit
import Foundation

// @Model classes could conform to Encodable, but DTOs decouple CLI output format
// from the data model — lets us flatten relationships (counts, IDs) without
// encoding cycles or leaking internal details like stateRawValue.

func printJSON<T: Encodable>(_ value: T, pretty: Bool) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
    let data = try encoder.encode(value)
    print(String(data: data, encoding: .utf8)!)
}

struct LogEntryDTO: Encodable {
    let id: UUID
    let timestamp: Date
    let source: String
    let isPrivate: Bool
    let title: String
    /// Nil in `log list` for a private entry; `show` has it.
    let content: String?
    let tags: [String]
    /// Names of the people the entry tags.
    let people: [String]
    let externalURL: URL?

    /// For lists: a private entry's content is left to `show`.
    static func listed(_ e: LogEntry) -> LogEntryDTO {
        let dto = from(e)
        return e.isPrivate ? LogEntryDTO(id: dto.id, timestamp: dto.timestamp, source: dto.source, isPrivate: true, title: dto.title,
                                         content: nil, tags: dto.tags, people: dto.people, externalURL: dto.externalURL) : dto
    }

    static func from(_ e: LogEntry) -> LogEntryDTO {
        LogEntryDTO(
            id: e.id,
            timestamp: e.timestamp,
            source: e.source.rawValue,
            isPrivate: e.isPrivate,
            title: e.title,
            content: e.content,
            tags: e.tags,
            people: e.people.map(\.name).sorted(),
           
            externalURL: e.externalURL
        )
    }
}

struct MeetingDTO: Encodable {
    let id: UUID
    let date: Date
    let title: String
    let isPrivate: Bool
    let attendeeCount: Int
    let tags: [String]
    let hasNotes: Bool
    let hasSummary: Bool
    let slackURL: URL?

    static func from(_ m: Meeting) -> MeetingDTO {
        MeetingDTO(
            id: m.id,
            date: m.date,
            title: m.title,
            isPrivate: m.isPrivate,
            attendeeCount: m.attendees.count,
            tags: m.tags,
           
            hasNotes: m.notes != nil,
            hasSummary: m.summary != nil,
            slackURL: m.slackURL
        )
    }
}

struct PullRequestDTO: Encodable {
    let id: UUID
    let number: Int
    let title: String
    let url: URL
    let repo: String
    /// The author's name, or their GitHub login when that's all sync knows.
    let author: String?
    let state: String
    let status: String
    let isDraft: Bool
    let deploymentStatus: String
    let isAuthoredByMe: Bool
    let isReviewRequest: Bool
    let myReviewedAt: Date?
    let reviewDecision: String?
    let createdAt: Date
    let mergedAt: Date?
    let additions: Int?
    let deletions: Int?
    let hasNotes: Bool

    static func from(_ pr: PullRequest) -> PullRequestDTO {
        PullRequestDTO(
            id: pr.id,
            number: pr.number,
            title: pr.title,
            url: pr.url,
            repo: pr.repo,
            author: pr.author?.name,
            state: pr.state.rawValue,
            status: pr.displayStatus.rawValue,
            isDraft: pr.isDraft,
            deploymentStatus: pr.deploymentStatus.rawValue,
            isAuthoredByMe: pr.isAuthoredByMe,
            isReviewRequest: pr.isReviewRequest,
            myReviewedAt: pr.myReviewedAt,
            reviewDecision: pr.reviewDecision?.rawValue,
            createdAt: pr.createdAt,
            mergedAt: pr.mergedAt,
            additions: pr.additions,
            deletions: pr.deletions,
           
            hasNotes: pr.notes != nil
        )
    }
}

struct TodoDTO: Encodable {
    let id: UUID
    let title: String
    var notes: String?
    let dueDate: Date?
    let completedDate: Date?
    let trashedDate: Date?
    let isCompleted: Bool
    let isPrivate: Bool
    let schedule: String
    let list: String
    let project: String?
    /// Names of the people the todo tags.
    let people: [String]

    /// For lists: a private todo's notes are left to `show`.
    static func listed(_ t: Todo) -> TodoDTO {
        var dto = from(t)
        if t.isPrivate { dto.notes = nil }
        return dto
    }

    static func from(_ t: Todo) -> TodoDTO {
        TodoDTO(
            id: t.id,
            title: t.title,
            notes: t.notes,
            dueDate: t.dueDate,
            completedDate: t.completedDate,
            trashedDate: t.trashedDate,
            isCompleted: t.isCompleted,
           
            isPrivate: t.isPrivate,
            schedule: t.schedule.rawValue,
            list: SmartList.of(t).rawValue,
            project: t.project?.name,
            people: t.people.map(\.name).sorted()
        )
    }
}

struct ProjectDTO: Encodable {
    let id: UUID
    let name: String
    let notes: String?
    let iconName: String?
    let isCompleted: Bool
    let completedDate: Date?
    let openTodoCount: Int

    static func from(_ p: Project) -> ProjectDTO {
        ProjectDTO(
            id: p.id,
            name: p.name,
            notes: p.notes,
            iconName: p.iconName,
            isCompleted: p.isCompleted,
            completedDate: p.completedDate,
            openTodoCount: (p.todos ?? []).filter { !$0.isCompleted && !$0.isTrashed }.count
        )
    }
}

struct PersonDTO: Encodable {
    let id: UUID
    let name: String
    let email: String?
    let slackHandle: String?
    let githubHandle: String?
    let syncsPullRequests: Bool
    let isSelf: Bool
    let meetingCount: Int
    let feedbackCount: Int

    static func from(_ p: Person) -> PersonDTO {
        PersonDTO(
            id: p.id,
            name: p.name,
            email: p.email,
            slackHandle: p.slackHandle,
            githubHandle: p.githubHandle,
            syncsPullRequests: p.syncsPullRequests,
            isSelf: p.isSelf,
            meetingCount: (p.meetings ?? []).count,
            feedbackCount: (p.feedback ?? []).count
        )
    }
}

struct CalendarEventDTO: Encodable {
    let id: UUID
    let title: String
    let startTime: Date
    let endTime: Date
    let isAllDay: Bool
    let isRecurring: Bool
    let isHidden: Bool
    let location: String?
    let meetingURL: URL?
    let attendeeCount: Int
    let meetingID: UUID?
    let interviewID: UUID?

    static func from(_ e: CalendarEvent) -> CalendarEventDTO {
        CalendarEventDTO(
            id: e.id,
            title: e.title,
            startTime: e.startTime,
            endTime: e.endTime,
            isAllDay: e.isAllDay,
            isRecurring: e.isRecurring,
            isHidden: e.isHidden,
            location: e.location,
            meetingURL: e.meetingURL,
            attendeeCount: e.attendees.count,
            meetingID: e.meeting?.id,
            interviewID: e.interview?.id
        )
    }
}

struct InterviewDTO: Encodable {
    let id: UUID
    let date: Date
    let candidateName: String
    let role: String?
    let isPrivate: Bool
    let recommendation: String?
    let hasNotes: Bool
    let hasConclusion: Bool

    static func from(_ i: Interview) -> InterviewDTO {
        InterviewDTO(
            id: i.id,
            date: i.date,
            candidateName: i.candidateName,
            role: i.role,
            isPrivate: i.isPrivate,
            recommendation: i.recommendation?.rawValue,
           
            hasNotes: i.rawNotes != nil,
            hasConclusion: i.conclusion != nil
        )
    }
}

struct SearchResultDTO: Encodable {
    let type: String
    let id: UUID
    let title: String
    let date: Date?
    let isPrivate: Bool
    let matchedField: String
    /// Nil for a private record, unless the match was in its title.
    let snippet: String?

    init(_ hit: SearchHit) {
        type = hit.kind.rawValue
        id = hit.id
        title = hit.title
        date = hit.date
        isPrivate = hit.isPrivate
        matchedField = hit.match.field
        let inTitle = hit.match.field == "title" || hit.match.field == "candidateName"
        snippet = hit.isPrivate && !inTitle ? nil : hit.match.snippet
    }
}
