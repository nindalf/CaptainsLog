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

    @Test func interviewKeepsRecordNameLevelAndDecision() throws {
        let now = Date(timeIntervalSince1970: 1_100_000_000)
        let interview = Interview(date: days(40, before: now), candidateName: "Dana", role: "Backend")
        interview.rawNotes = "notes"
        interview.upsides = "up"
        interview.riskFactors = "risk"
        interview.conclusion = "done"
        interview.debriefNotes = "debrief"
        interview.whiteboardLink = "https://board"
        interview.levelAssessment = "L4"
        interview.recommendation = .strongYes
        interview.problemName = "LRU cache"
        let recent = Interview(date: days(10, before: now), candidateName: "Eli")
        recent.rawNotes = "fresh"
        let lateDebrief = Interview(date: days(40, before: now), candidateName: "Fay")
        lateDebrief.rawNotes = "kept"
        lateDebrief.debriefDate = days(5, before: now)
        context.insert(interview)
        context.insert(recent)
        context.insert(lateDebrief)
        try context.save()

        let expired = try ExpiredRecords.find(settings(interviews: true), now: now, in: context)
        let ids = Set(expired.interviews.map(\.id))
        #expect(ids.contains(interview.id))
        #expect(!ids.contains(recent.id))
        #expect(!ids.contains(lateDebrief.id))
        try expired.remove(in: context)

        #expect(interview.rawNotes == nil && interview.upsides == nil && interview.riskFactors == nil)
        #expect(interview.conclusion == nil && interview.debriefNotes == nil && interview.whiteboardLink == nil)
        #expect(interview.candidateName == "Dana" && interview.role == "Backend")
        #expect(interview.levelAssessment == "L4" && interview.recommendation == .strongYes && interview.problemName == "LRU cache")
        #expect(recent.rawNotes == "fresh" && lateDebrief.rawNotes == "kept")

        // Cleared once, it isn't found again.
        let again = try ExpiredRecords.find(settings(interviews: true), now: now, in: context)
        #expect(!again.interviews.contains { $0.id == interview.id })
    }

    @Test func calendarEventsKeepWrittenMeetingsAndInterviews() throws {
        let now = Date(timeIntervalSince1970: 1_200_000_000)
        func event(_ name: String, daysAgo: Int) -> CalendarEvent {
            let start = days(daysAgo, before: now)
            let e = CalendarEvent(title: name, startTime: start, endTime: start.addingTimeInterval(1800), externalID: "retention-\(name)-\(now.timeIntervalSince1970)")
            context.insert(e)
            return e
        }
        let bare = event("bare", daysAgo: 200)
        let stub = event("stub", daysAgo: 200)
        let stubMeeting = Meeting(date: stub.startTime, title: "stub")
        stubMeeting.calendarEvent = stub
        context.insert(stubMeeting)
        let written = event("written", daysAgo: 200)
        let writtenMeeting = Meeting(date: written.startTime, title: "written")
        writtenMeeting.notes = "we decided"
        writtenMeeting.calendarEvent = written
        context.insert(writtenMeeting)
        let interviewed = event("interviewed", daysAgo: 200)
        let interview = Interview(date: interviewed.startTime, candidateName: "Gus")
        interview.calendarEvent = interviewed
        context.insert(interview)
        let recent = event("recent", daysAgo: 100)
        try context.save()

        let expired = try ExpiredRecords.find(settings(calendarEvents: true), now: now, in: context)
        let ids = Set(expired.calendarEvents.map(\.id))
        #expect(ids.isSuperset(of: [bare.id, stub.id]))
        #expect(!ids.contains(written.id) && !ids.contains(interviewed.id) && !ids.contains(recent.id))

        let stubMeetingID = stubMeeting.id
        let writtenMeetingID = writtenMeeting.id
        try expired.remove(in: context)
        let meetings = try context.fetch(FetchDescriptor<Meeting>()).map(\.id)
        #expect(!meetings.contains(stubMeetingID))
        #expect(meetings.contains(writtenMeetingID))
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
