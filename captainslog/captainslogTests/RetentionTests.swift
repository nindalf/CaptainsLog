import Foundation
import SwiftData
import Testing
import CaptainsLogKit

// One shared in-memory container, serialized: see PersonMergeTests. Every test dates its records far in
// the past relative to its own `now`, and checks only the records it made, by id.
@Suite(.serialized)
@MainActor
struct RetentionTests {
    private static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: Schema(CaptainsLogSchema.models), configurations: [config])
    }()

    private var context: ModelContext { Self.container.mainContext }

    private func days(_ n: Int, before date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: date)!
    }

    private func settings(interviews: Bool = false, calendarEvents: Bool = false, pullRequests: Bool = false) -> RetentionSettings {
        var s = RetentionSettings()
        s.interviews.isEnabled = interviews
        s.calendarEvents.isEnabled = calendarEvents
        s.pullRequests.isEnabled = pullRequests
        return s
    }

    @Test func offRulesFindNothing() throws {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let old = Interview(date: days(400, before: now), candidateName: "Old")
        old.rawNotes = "notes"
        context.insert(old)
        try context.save()

        let expired = try ExpiredRecords.find(settings(), now: now, in: context)
        #expect(expired.isEmpty)
    }

    private func event(_ name: String, daysAgo: Int, before now: Date) -> CalendarEvent {
        let start = days(daysAgo, before: now)
        let e = CalendarEvent(title: name, startTime: start, endTime: start.addingTimeInterval(1800), externalID: "retention-\(name)-\(now.timeIntervalSince1970)")
        context.insert(e)
        return e
    }

    private func todo(_ title: String, completed: Bool = false, trashed: Bool = false) -> Todo {
        let t = Todo(title: title)
        if completed { t.completedDate = .now }
        if trashed { t.trashedDate = .now }
        context.insert(t)
        return t
    }

    private func ids<T: PersistentModel>(_ type: T.Type, _ id: KeyPath<T, UUID>) throws -> Set<UUID> {
        Set(try context.fetch(FetchDescriptor<T>()).map { $0[keyPath: id] })
    }

    @Test func interviewsGoWithEventAndTodosOnceNoTodoIsOpen() throws {
        let now = Date(timeIntervalSince1970: 1_100_000_000)
        func interview(_ name: String, daysAgo: Int) -> Interview {
            let i = Interview(date: days(daysAgo, before: now), candidateName: name)
            i.rawNotes = "notes"
            context.insert(i)
            return i
        }
        let submitted = interview("Dana", daysAgo: 40)
        let submittedEvent = event("Interview Dana", daysAgo: 40, before: now)
        submitted.calendarEvent = submittedEvent
        let scorecard = todo("Submit scorecard for Dana", completed: true)
        scorecard.interview = submitted
        let unsubmitted = interview("Eli", daysAgo: 40)
        todo("Submit scorecard for Eli").interview = unsubmitted
        let dismissed = interview("Fay", daysAgo: 40)
        todo("Submit scorecard for Fay", trashed: true).interview = dismissed
        let untouched = interview("Gus", daysAgo: 40)
        let recent = interview("Hal", daysAgo: 10)
        let lateDebrief = interview("Ida", daysAgo: 40)
        lateDebrief.debriefDate = days(5, before: now)
        try context.save()

        let expired = try ExpiredRecords.find(settings(interviews: true), now: now, in: context)
        let found = Set(expired.interviews.map(\.id))
        #expect(found.isSuperset(of: [submitted.id, dismissed.id, untouched.id]))
        #expect(found.isDisjoint(with: [unsubmitted.id, recent.id, lateDebrief.id]))

        let scorecardID = scorecard.id
        let eventID = submittedEvent.id
        try expired.remove(in: context)
        let interviews = try ids(Interview.self, \.id)
        #expect(interviews.isDisjoint(with: found))
        #expect(interviews.isSuperset(of: [unsubmitted.id, recent.id, lateDebrief.id]))
        #expect(!(try ids(Todo.self, \.id)).contains(scorecardID))
        #expect(!(try ids(CalendarEvent.self, \.id)).contains(eventID))
    }

    @Test func meetingsAndEventsGoWrittenOrNot() throws {
        let now = Date(timeIntervalSince1970: 1_200_000_000)
        let bare = event("bare", daysAgo: 200, before: now)
        let written = event("written", daysAgo: 200, before: now)
        let writtenMeeting = written.createMeeting(in: context)
        writtenMeeting.notes = "we decided"
        let followUp = todo("Follow up")
        followUp.meeting = writtenMeeting
        let adHoc = Meeting(date: days(200, before: now), title: "ad hoc")
        context.insert(adHoc)
        let recentMeeting = Meeting(date: days(100, before: now), title: "recent")
        context.insert(recentMeeting)
        let recent = event("recent", daysAgo: 100, before: now)
        let interviewed = event("interviewed", daysAgo: 200, before: now)
        let interview = Interview(date: interviewed.startTime, candidateName: "Jo")
        interview.calendarEvent = interviewed
        context.insert(interview)
        try context.save()

        let expired = try ExpiredRecords.find(settings(calendarEvents: true), now: now, in: context)
        let events = Set(expired.calendarEvents.map(\.id))
        let meetings = Set(expired.meetings.map(\.id))
        #expect(events.isSuperset(of: [bare.id, written.id]))
        #expect(events.isDisjoint(with: [recent.id, interviewed.id]))
        #expect(meetings.isSuperset(of: [writtenMeeting.id, adHoc.id]))
        #expect(!meetings.contains(recentMeeting.id))

        try expired.remove(in: context)
        #expect(try ids(Meeting.self, \.id).isDisjoint(with: meetings))
        #expect(try ids(CalendarEvent.self, \.id).isDisjoint(with: events))
        #expect(try ids(CalendarEvent.self, \.id).contains(interviewed.id))
        #expect(try ids(Interview.self, \.id).contains(interview.id))
        #expect(followUp.meeting == nil && !followUp.isDeleted)
    }

    /// PRs are removed before interviews, so unlinking a PR's todos doesn't touch one an interview deleted.
    /// Dated before every other test's records, so this run removes only its own.
    @Test func everyRuleAtOnce() throws {
        let now = Date(timeIntervalSince1970: 900_000_000)
        let interview = Interview(date: days(400, before: now), candidateName: "Kim")
        interview.calendarEvent = event("Interview Kim", daysAgo: 400, before: now)
        context.insert(interview)
        let pr = PullRequest(number: 1, title: "PR", url: URL(string: "https://x/1")!, repo: "retention/\(now.timeIntervalSince1970)", state: .merged, createdAt: days(400, before: now), isAuthoredByMe: true)
        context.insert(pr)
        let scorecard = todo("Submit scorecard for Kim", completed: true)
        scorecard.interview = interview
        scorecard.pullRequest = pr
        let meeting = event("sync", daysAgo: 400, before: now).createMeeting(in: context)
        meeting.notes = "notes"
        try context.save()

        let removed: Set<UUID> = [interview.id, pr.id, meeting.id, scorecard.id]
        let all = RetentionSettings()
        try ExpiredRecords.find(all, now: now, in: context).remove(in: context)
        let remaining = try ids(Interview.self, \.id).union(ids(PullRequest.self, \.id))
            .union(ids(Meeting.self, \.id)).union(ids(Todo.self, \.id))
        #expect(remaining.isDisjoint(with: removed))
        #expect(try ExpiredRecords.find(all, now: now, in: context).isEmpty)
    }

    @Test func pullRequestsGoByLastUpdateAndUnlinkTodos() throws {
        let now = Date(timeIntervalSince1970: 1_300_000_000)
        func pr(_ number: Int, createdDaysAgo: Int, updatedDaysAgo: Int?) -> PullRequest {
            let p = PullRequest(number: number, title: "PR \(number)", url: URL(string: "https://x/\(number)")!, repo: "retention/\(now.timeIntervalSince1970)", state: .merged, createdAt: days(createdDaysAgo, before: now), isAuthoredByMe: true)
            p.updatedAt = updatedDaysAgo.map { days($0, before: now) }
            context.insert(p)
            return p
        }
        let stale = pr(1, createdDaysAgo: 500, updatedDaysAgo: 400)
        let revived = pr(2, createdDaysAgo: 500, updatedDaysAgo: 10)
        let legacy = pr(3, createdDaysAgo: 500, updatedDaysAgo: nil)
        let project = Project(name: "Retention \(now.timeIntervalSince1970)")
        context.insert(project)
        stale.project = project
        let todo = Todo(title: "Follow up")
        todo.pullRequest = stale
        context.insert(todo)
        try context.save()

        let expired = try ExpiredRecords.find(settings(pullRequests: true), now: now, in: context)
        let ids = Set(expired.pullRequests.map(\.id))
        #expect(ids.contains(stale.id) && ids.contains(legacy.id))
        #expect(!ids.contains(revived.id))

        let staleID = stale.id
        try expired.remove(in: context)
        #expect(todo.pullRequest == nil)
        let remaining = try context.fetch(FetchDescriptor<PullRequest>()).map(\.id)
        #expect(!remaining.contains(staleID))
        #expect(remaining.contains(revived.id))
    }
}
