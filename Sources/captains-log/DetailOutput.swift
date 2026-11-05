import CaptainsLogKit
import Foundation

// Full records for `show`. List DTOs stay compact; these carry every field the app displays,
// untruncated, plus refs to linked records so their ids can be passed to the next command.
// Reading relationship arrays is fine here: each run fetches fresh from the store, so the
// stale-inverse problem views have doesn't arise.
// A private record's text comes out nil: the CLI's only reader is Claude, which keeps out of it.

struct RecordRef: Encodable {
    let id: UUID
    let title: String
}

struct PersonRef: Encodable {
    let id: UUID
    let name: String

    static func from(_ p: Person) -> PersonRef { PersonRef(id: p.id, name: p.name) }
}

extension RecordRef {
    static func from(_ p: Project) -> RecordRef { RecordRef(id: p.id, title: p.name) }
    static func from(_ m: Meeting) -> RecordRef { RecordRef(id: m.id, title: m.title) }
    static func from(_ i: Interview) -> RecordRef { RecordRef(id: i.id, title: i.candidateName) }
    static func from(_ pr: PullRequest) -> RecordRef { RecordRef(id: pr.id, title: "\(pr.repo)#\(pr.number) \(pr.title)") }
    static func from(_ e: LogEntry) -> RecordRef { RecordRef(id: e.id, title: e.title) }
    static func from(_ t: Todo) -> RecordRef { RecordRef(id: t.id, title: t.title) }
}

struct LogEntryDetail: Encodable {
    let type = "log"
    let id: UUID
    let timestamp: Date
    let source: String
    let isPrivate: Bool
    let title: String
    let content: String?
    let tags: [String]
    let externalURL: URL?
    let externalID: String?
    let project: RecordRef?
    let people: [PersonRef]

    static func from(_ e: LogEntry) -> LogEntryDetail {
        LogEntryDetail(
            id: e.id, timestamp: e.timestamp, source: e.source.rawValue, isPrivate: e.isPrivate,
            title: e.title, content: e.isPrivate ? nil : e.content, tags: e.tags,
            externalURL: e.externalURL, externalID: e.externalID,
            project: e.project.map(RecordRef.from), people: e.people.map(PersonRef.from)
        )
    }
}

struct MeetingDetail: Encodable {
    let type = "meeting"
    let id: UUID
    let date: Date
    let title: String
    let isPrivate: Bool
    let tags: [String]
    let project: RecordRef?
    let attendees: [PersonRef]
    let prepNotes: String?
    let notes: String?
    let transcript: String?
    let summary: String?
    let externalURL: URL?
    let slackURL: URL?
    let calendarEventID: UUID?
    let todos: [RecordRef]

    static func from(_ m: Meeting, todos: [Todo]) -> MeetingDetail {
        MeetingDetail(
            id: m.id, date: m.date, title: m.title, isPrivate: m.isPrivate, tags: m.tags,
            project: m.project.map(RecordRef.from),
            attendees: m.attendees.sorted { $0.name < $1.name }.map(PersonRef.from),
            prepNotes: m.isPrivate ? nil : m.prepNotes, notes: m.isPrivate ? nil : m.notes,
            transcript: m.isPrivate ? nil : m.transcript, summary: m.isPrivate ? nil : m.summary,
            externalURL: m.externalURL, slackURL: m.slackURL, calendarEventID: m.calendarEvent?.id,
            todos: todos.map(RecordRef.from)
        )
    }
}

struct InterviewDetail: Encodable {
    let type = "interview"
    let id: UUID
    let date: Date
    let candidateName: String
    let role: String?
    let isPrivate: Bool
    let problemName: String?
    let whiteboardLink: String?
    let coInterviewer: PersonRef?
    let rawNotes: String?
    let upsides: String?
    let riskFactors: String?
    let levelAssessment: String?
    let recommendation: String?
    let conclusion: String?
    let debriefDate: Date?
    let debriefNotes: String?
    let calendarEventID: UUID?
    let todos: [RecordRef]

    static func from(_ i: Interview, todos: [Todo]) -> InterviewDetail {
        func text(_ value: String?) -> String? { i.isPrivate ? nil : value }
        return InterviewDetail(
            id: i.id, date: i.date, candidateName: i.candidateName, role: i.role,
            isPrivate: i.isPrivate,
            problemName: i.problemName, whiteboardLink: text(i.whiteboardLink),
            coInterviewer: i.coInterviewer.map(PersonRef.from),
            rawNotes: text(i.rawNotes), upsides: text(i.upsides), riskFactors: text(i.riskFactors),
            levelAssessment: text(i.levelAssessment), recommendation: i.recommendation?.rawValue,
            conclusion: text(i.conclusion), debriefDate: i.debriefDate, debriefNotes: text(i.debriefNotes),
            calendarEventID: i.calendarEvent?.id, todos: todos.map(RecordRef.from)
        )
    }
}

struct PullRequestDetail: Encodable {
    let type = "pr"
    let id: UUID
    let number: Int
    let title: String
    let url: URL
    let repo: String
    let state: String
    let status: String
    let isDraft: Bool
    let deploymentStatus: String
    let reviewDecision: String?
    let isAuthoredByMe: Bool
    let isReviewRequest: Bool
    let myReviewedAt: Date?
    let author: PersonRef?
    let reviewers: [PersonRef]
    let createdAt: Date
    let mergedAt: Date?
    let additions: Int?
    let deletions: Int?
    let tags: [String]
    let project: RecordRef?
    let body: String?
    let notes: String?
    let todos: [RecordRef]

    static func from(_ pr: PullRequest, todos: [Todo]) -> PullRequestDetail {
        PullRequestDetail(
            id: pr.id, number: pr.number, title: pr.title, url: pr.url, repo: pr.repo,
            state: pr.state.rawValue, status: pr.displayStatus.rawValue, isDraft: pr.isDraft,
            deploymentStatus: pr.deploymentStatus.rawValue, reviewDecision: pr.reviewDecision?.rawValue,
            isAuthoredByMe: pr.isAuthoredByMe, isReviewRequest: pr.isReviewRequest,
            myReviewedAt: pr.myReviewedAt, author: pr.author.map(PersonRef.from),
            reviewers: pr.reviewers.sorted { $0.name < $1.name }.map(PersonRef.from),
            createdAt: pr.createdAt, mergedAt: pr.mergedAt, additions: pr.additions, deletions: pr.deletions,
            tags: pr.tags, project: pr.project.map(RecordRef.from),
            body: pr.body, notes: pr.notes, todos: todos.map(RecordRef.from)
        )
    }
}

struct TodoDetail: Encodable {
    let type = "todo"
    let id: UUID
    let title: String
    let notes: String?
    let dueDate: Date?
    let completedDate: Date?
    let trashedDate: Date?
    let isCompleted: Bool
    let isPrivate: Bool
    let schedule: String
    let list: String
    let project: RecordRef?
    let people: [PersonRef]
    let meeting: RecordRef?
    let interview: RecordRef?
    let pullRequest: RecordRef?

    static func from(_ t: Todo) -> TodoDetail {
        TodoDetail(
            id: t.id, title: t.title, notes: t.isPrivate ? nil : t.notes, dueDate: t.dueDate, completedDate: t.completedDate,
            trashedDate: t.trashedDate, isCompleted: t.isCompleted,
            isPrivate: t.isPrivate, schedule: t.schedule.rawValue, list: SmartList.of(t).rawValue,
            project: t.project.map(RecordRef.from), people: t.people.map(PersonRef.from),
            meeting: t.meeting.map(RecordRef.from), interview: t.interview.map(RecordRef.from),
            pullRequest: t.pullRequest.map(RecordRef.from)
        )
    }
}

struct ProjectDetail: Encodable {
    let type = "project"
    let id: UUID
    let name: String
    let notes: String?
    let iconName: String?
    let isCompleted: Bool
    let completedDate: Date?
    let todos: [RecordRef]
    let completedTodos: [RecordRef]
    let meetings: [RecordRef]
    let pullRequests: [RecordRef]
    let logEntries: [RecordRef]

    static func from(_ p: Project) -> ProjectDetail {
        let todos = (p.todos ?? []).filter { !$0.isTrashed }.sorted { $0.sortOrder < $1.sortOrder }
        return ProjectDetail(
            id: p.id, name: p.name, notes: p.notes, iconName: p.iconName, isCompleted: p.isCompleted,
            completedDate: p.completedDate,
            todos: todos.filter { !$0.isCompleted }.map(RecordRef.from),
            completedTodos: todos.filter(\.isCompleted).map(RecordRef.from),
            meetings: (p.meetings ?? []).sorted { $0.date > $1.date }.map(RecordRef.from),
            pullRequests: (p.pullRequests ?? []).sorted { $0.createdAt > $1.createdAt }.map(RecordRef.from),
            logEntries: (p.logEntries ?? []).sorted { $0.timestamp > $1.timestamp }.map(RecordRef.from)
        )
    }
}

struct FeedbackDetail: Encodable {
    let type = "feedback"
    let id: UUID
    let date: Date
    let person: PersonRef
    let content: String

    static func from(_ f: Feedback) -> FeedbackDetail {
        FeedbackDetail(
            id: f.id, date: f.date, person: PersonRef.from(f.person),
            content: f.content
        )
    }
}

struct PersonDetail: Encodable {
    let type = "person"
    let id: UUID
    let name: String
    let email: String?
    let slackHandle: String?
    let githubHandle: String?
    let syncsPullRequests: Bool
    let isSelf: Bool
    let feedback: [FeedbackDetail]
    let meetings: [RecordRef]
    let interviews: [RecordRef]
    let authoredPRs: [RecordRef]
    let reviewedPRs: [RecordRef]
    /// Entries that tag them.
    let logEntries: [RecordRef]

    static func from(_ p: Person) -> PersonDetail {
        PersonDetail(
            id: p.id, name: p.name, email: p.email, slackHandle: p.slackHandle, githubHandle: p.githubHandle,
            syncsPullRequests: p.syncsPullRequests, isSelf: p.isSelf,
            feedback: (p.feedback ?? []).sorted { $0.date > $1.date }.map(FeedbackDetail.from),
            meetings: (p.meetings ?? []).sorted { $0.date > $1.date }.map(RecordRef.from),
            interviews: (p.interviews ?? []).sorted { $0.date > $1.date }.map(RecordRef.from),
            authoredPRs: (p.authoredPRs ?? []).sorted { $0.createdAt > $1.createdAt }.map(RecordRef.from),
            reviewedPRs: (p.reviewedPRs ?? []).sorted { $0.createdAt > $1.createdAt }.map(RecordRef.from),
            logEntries: (p.logEntries ?? []).sorted { $0.timestamp > $1.timestamp }.map(RecordRef.from)
        )
    }
}

struct CalendarEventDetail: Encodable {
    let type = "event"
    let id: UUID
    let title: String
    let startTime: Date
    let endTime: Date
    let isAllDay: Bool
    let isRecurring: Bool
    let isHidden: Bool
    let location: String?
    let meetingURL: URL?
    let participantCount: Int
    let confirmedCount: Int
    let attendees: [PersonRef]
    let meeting: RecordRef?
    let interview: RecordRef?

    static func from(_ e: CalendarEvent) -> CalendarEventDetail {
        CalendarEventDetail(
            id: e.id, title: e.title, startTime: e.startTime, endTime: e.endTime, isAllDay: e.isAllDay,
            isRecurring: e.isRecurring, isHidden: e.isHidden, location: e.location, meetingURL: e.meetingURL,
            participantCount: e.participantCount, confirmedCount: e.confirmedCount,
            attendees: e.attendees.sorted { $0.name < $1.name }.map(PersonRef.from),
            meeting: e.meeting.map(RecordRef.from), interview: e.interview.map(RecordRef.from)
        )
    }
}
