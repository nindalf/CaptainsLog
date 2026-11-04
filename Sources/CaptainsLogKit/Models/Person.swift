import Foundation
import SwiftData

@Model
public final class Person {
    public var id: UUID = UUID()
    public var name: String
    public var email: String?
    public var slackHandle: String?
    public var githubHandle: String?
    /// Sync every PR they author in the configured repos, not just the ones asking for my review.
    public var syncsPullRequests: Bool = false
    /// The app's user. At most one person has it; set through `markAsSelf(in:)`.
    public var isSelf: Bool = false

    #Index<Person>([\.email], [\.slackHandle], [\.githubHandle])

    @Relationship(deleteRule: .nullify, inverse: \LogEntry.people)
    public var logEntries: [LogEntry]?
    @Relationship(deleteRule: .nullify, inverse: \Meeting.attendees)
    public var meetings: [Meeting]?
    @Relationship(deleteRule: .nullify, inverse: \CalendarEvent.attendees)
    public var calendarEvents: [CalendarEvent]?
    @Relationship(deleteRule: .nullify, inverse: \PullRequest.author)
    public var authoredPRs: [PullRequest]?
    @Relationship(deleteRule: .nullify, inverse: \PullRequest.reviewers)
    public var reviewedPRs: [PullRequest]?
    @Relationship(deleteRule: .nullify, inverse: \Todo.people)
    public var todos: [Todo]?
    @Relationship(deleteRule: .cascade, inverse: \Feedback.person)
    public var feedback: [Feedback]?
    @Relationship(deleteRule: .nullify, inverse: \Interview.coInterviewer)
    public var interviews: [Interview]?

    public init(
        name: String,
        email: String? = nil,
        slackHandle: String? = nil,
        githubHandle: String? = nil
    ) {
        self.name = name
        self.email = email
        self.slackHandle = slackHandle
        self.githubHandle = githubHandle
        trimWhitespace()
    }

    /// Strips leading and trailing whitespace from the name, email and handles, and clears
    /// an email or handle left empty. Call before saving an edit.
    public func trimWhitespace() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName != name { name = trimmedName }
        for keyPath in [\Person.email, \Person.slackHandle, \Person.githubHandle] {
            guard let value = self[keyPath: keyPath] else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != value { self[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed }
        }
    }
}
