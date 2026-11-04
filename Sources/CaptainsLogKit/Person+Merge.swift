import Foundation
import SwiftData

extension Person {
    /// A contact worth surfacing in the People tab: has at least one association
    /// beyond being a raw calendar attendee. Filters out the noise created by
    /// syncing every event attendee.
    public var isMeaningfulContact: Bool {
        !(meetings ?? []).isEmpty
            || !(feedback ?? []).isEmpty
            || !(authoredPRs ?? []).isEmpty
            || !(reviewedPRs ?? []).isEmpty
            || !(logEntries ?? []).isEmpty
            || !(todos ?? []).isEmpty
            || !(interviews ?? []).isEmpty
    }

    /// Rough relevance score used to rank the People list. More real
    /// associations means higher up.
    public var activityScore: Int {
        (meetings ?? []).count
            + (authoredPRs ?? []).count
            + (reviewedPRs ?? []).count
            + (feedback ?? []).count * 2
            + (logEntries ?? []).count
            + (todos ?? []).count
            + (interviews ?? []).count
    }

    /// Reassign every relationship from `other` onto `self`, backfill any empty
    /// profile fields, then delete `other`. Used to fold a duplicate (e.g. the
    /// GitHub-handle record and the calendar-email record for one human) into a
    /// single person.
    ///
    /// Must run on the actor that owns `context` — `@Model` is not `Sendable`.
    public func absorb(_ other: Person, in context: ModelContext) {
        guard other.id != id else { return }

        // For to-many relationships, only add `self` where it's missing.
        // `context.delete(other)` removes `other` from every to-many via the
        // `.nullify` delete rule; removing it manually here too would mutate the
        // same relationship twice in one save and traps inside SwiftData.
        // To-one links (`author`, `feedback.person`, `coInterviewer`) must be
        // reassigned explicitly — nullify would drop them, and `feedback`
        // cascade-deletes.
        for pr in other.authoredPRs ?? [] {
            pr.author = self
        }
        for pr in other.reviewedPRs ?? [] {
            Self.addIfMissing(&pr.reviewers, self)
        }
        for meeting in other.meetings ?? [] {
            Self.addIfMissing(&meeting.attendees, self)
        }
        for event in other.calendarEvents ?? [] {
            Self.addIfMissing(&event.attendees, self)
        }
        for entry in other.logEntries ?? [] {
            Self.addIfMissing(&entry.people, self)
        }
        for todo in other.todos ?? [] {
            Self.addIfMissing(&todo.people, self)
        }
        for item in other.feedback ?? [] {
            item.person = self
        }
        for interview in other.interviews ?? [] {
            interview.coInterviewer = self
        }

        if email == nil { email = other.email }
        if slackHandle == nil { slackHandle = other.slackHandle }
        if githubHandle == nil { githubHandle = other.githubHandle }
        if other.syncsPullRequests { syncsPullRequests = true }
        if other.isSelf { isSelf = true }

        context.delete(other)
    }

    private static func addIfMissing(_ people: inout [Person], _ keep: Person) {
        if !people.contains(where: { $0.id == keep.id }) {
            people.append(keep)
        }
    }
}
