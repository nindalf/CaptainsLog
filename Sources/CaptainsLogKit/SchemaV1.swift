import Foundation
import SwiftData

// Frozen: the models as released in v0.10.0, so the migration plan can recognise a store written
// by them. Never edit; a model change goes in the top-level classes and a new schema version.
// Stored properties, relationships, constraints and indexes only.
public enum CaptainsLogSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Person.self,
            Project.self,
            LogEntry.self,
            CalendarEvent.self,
            Meeting.self,
            PullRequest.self,
            Interview.self,
            Feedback.self,
            Todo.self,
        ]
    }

    @Model
    final class CalendarEvent {
        var id: UUID = UUID()
        var title: String
        var startTime: Date
        var endTime: Date
        var attendees: [Person] = []
        var location: String?
        var meetingURL: URL?
        var isRecurring: Bool = false
        var isAllDay: Bool = false
        var participantCount: Int = 0
        var confirmedCount: Int = 0
        var externalID: String
        var isHidden: Bool = false

        #Unique<CalendarEvent>([\.externalID])

        @Relationship(deleteRule: .nullify, inverse: \Meeting.calendarEvent)
        var meeting: Meeting?
        @Relationship(deleteRule: .nullify, inverse: \Interview.calendarEvent)
        var interview: Interview?

        init(title: String, startTime: Date, endTime: Date, externalID: String) {
            self.title = title
            self.startTime = startTime
            self.endTime = endTime
            self.externalID = externalID
        }
    }

    @Model
    final class Feedback {
        var id: UUID = UUID()
        var date: Date
        var person: Person
        var content: String

        init(date: Date, person: Person, content: String) {
            self.date = date
            self.person = person
            self.content = content
        }
    }

    @Model
    final class Interview {
        var id: UUID = UUID()
        var date: Date
        var candidateName: String
        var role: String?
        var problemName: String?
        var whiteboardLink: String?
        var calendarEvent: CalendarEvent?
        var isPrivate: Bool = true
        var rawNotes: String?
        var upsides: String?
        var riskFactors: String?
        var levelAssessment: String?
        var recommendation: Recommendation?
        var conclusion: String?
        var coInterviewer: Person?
        var debriefDate: Date?
        var debriefNotes: String?
        @Relationship(deleteRule: .nullify, inverse: \Todo.interview)
        var todos: [Todo]?

        #Index<Interview>([\.date])

        init(date: Date, candidateName: String) {
            self.date = date
            self.candidateName = candidateName
        }
    }

    @Model
    final class LogEntry {
        var id: UUID = UUID()
        var timestamp: Date
        var source: EntrySource
        var isPrivate: Bool = false
        var title: String
        var content: String
        var people: [Person] = []
        var project: Project?
        var tags: [String] = []
        var externalURL: URL?

        #Index<LogEntry>([\.timestamp])

        var externalID: String?

        init(timestamp: Date, source: EntrySource, title: String, content: String) {
            self.timestamp = timestamp
            self.source = source
            self.title = title
            self.content = content
        }
    }

    @Model
    final class Meeting {
        var id: UUID = UUID()
        var calendarEvent: CalendarEvent?
        var date: Date
        var title: String
        var attendees: [Person] = []
        var isPrivate: Bool = false
        var project: Project?
        var tags: [String] = []
        var prepNotes: String?
        var notes: String?
        var transcript: String?
        var summary: String?
        var externalURL: URL?
        var slackURL: URL?
        @Relationship(deleteRule: .nullify, inverse: \Todo.meeting)
        var todos: [Todo]?
        @Relationship(deleteRule: .nullify, inverse: \Todo.completedInMeeting)
        var completedTodos: [Todo]?

        #Index<Meeting>([\.date])

        init(date: Date, title: String) {
            self.date = date
            self.title = title
        }
    }

    @Model
    final class Person {
        var id: UUID = UUID()
        var name: String
        var email: String?
        var slackHandle: String?
        var githubHandle: String?
        var syncsPullRequests: Bool = false
        var isSelf: Bool = false

        #Index<Person>([\.email], [\.slackHandle], [\.githubHandle])

        @Relationship(deleteRule: .nullify, inverse: \LogEntry.people)
        var logEntries: [LogEntry]?
        @Relationship(deleteRule: .nullify, inverse: \Meeting.attendees)
        var meetings: [Meeting]?
        @Relationship(deleteRule: .nullify, inverse: \CalendarEvent.attendees)
        var calendarEvents: [CalendarEvent]?
        @Relationship(deleteRule: .nullify, inverse: \PullRequest.author)
        var authoredPRs: [PullRequest]?
        @Relationship(deleteRule: .nullify, inverse: \PullRequest.reviewers)
        var reviewedPRs: [PullRequest]?
        @Relationship(deleteRule: .nullify, inverse: \Todo.people)
        var todos: [Todo]?
        @Relationship(deleteRule: .cascade, inverse: \Feedback.person)
        var feedback: [Feedback]?
        @Relationship(deleteRule: .nullify, inverse: \Interview.coInterviewer)
        var interviews: [Interview]?

        init(name: String) {
            self.name = name
        }
    }

    @Model
    final class Project {
        var id: UUID = UUID()
        var name: String
        var notes: String?
        var completedDate: Date?
        var sortOrder: Int = 0
        var iconName: String?

        #Unique<Project>([\.name])

        @Relationship(deleteRule: .nullify, inverse: \LogEntry.project)
        var logEntries: [LogEntry]?
        @Relationship(deleteRule: .nullify, inverse: \Meeting.project)
        var meetings: [Meeting]?
        @Relationship(deleteRule: .nullify, inverse: \PullRequest.project)
        var pullRequests: [PullRequest]?
        @Relationship(deleteRule: .nullify, inverse: \Todo.project)
        var todos: [Todo]?

        init(name: String) {
            self.name = name
        }
    }

    @Model
    final class PullRequest {
        var id: UUID = UUID()
        var number: Int
        var title: String
        var body: String?
        var url: URL
        var repo: String
        var stateRawValue: String = "open"
        var author: Person?
        var reviewers: [Person] = []
        var reviewDecision: ReviewDecision?
        var createdAt: Date
        var mergedAt: Date?
        var updatedAt: Date?
        var additions: Int?
        var deletions: Int?
        var isAuthoredByMe: Bool
        var isTeammateOnly: Bool = false
        var myReviewedAt: Date?
        var project: Project?
        var tags: [String] = []
        var isDraft: Bool = false
        var deploymentStatus: DeploymentStatus = DeploymentStatus.notDeployed
        var notes: String?

        #Unique<PullRequest>([\.repo, \.number])
        #Index<PullRequest>([\.stateRawValue])

        init(number: Int, title: String, url: URL, repo: String, createdAt: Date, isAuthoredByMe: Bool) {
            self.number = number
            self.title = title
            self.url = url
            self.repo = repo
            self.createdAt = createdAt
            self.isAuthoredByMe = isAuthoredByMe
        }
    }

    @Model
    final class Todo {
        var id: UUID = UUID()
        var title: String
        var notes: String?
        var dueDate: Date?
        var completedDate: Date?
        var trashedDate: Date?
        var isPrivate: Bool = false
        var sortOrder: Int = 0
        var scheduleRawValue: String = "anytime"
        var people: [Person] = []
        var project: Project?
        var meeting: Meeting?
        var completedInMeeting: Meeting?
        var interview: Interview?
        var pullRequest: PullRequest?

        #Index<Todo>([\.dueDate], [\.completedDate])

        init(title: String) {
            self.title = title
        }
    }
}
