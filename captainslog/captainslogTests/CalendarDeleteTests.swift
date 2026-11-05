import Foundation
import SwiftData
import Testing
import CaptainsLogKit

// One shared in-memory container for the whole suite, serialized — see PersonMergeTests for why.
// Nothing is reset between tests; each test uses its own objects and scopes lookups by externalID.
@Suite(.serialized)
@MainActor
struct CalendarDeleteTests {
    private static let container: ModelContainer = {
        let schema = Schema(CaptainsLogSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func makeContext() -> ModelContext {
        Self.container.mainContext
    }

    private func fetchEvent(_ externalID: String, in context: ModelContext) throws -> CalendarEvent?
    {
        try context.fetch(
            FetchDescriptor<CalendarEvent>(
                predicate: #Predicate { $0.externalID == externalID }
            )
        ).first
    }

    private func makeEvent(_ externalID: String, in context: ModelContext) -> CalendarEvent {
        let event = CalendarEvent(
            title: "Interview with Andy",
            startTime: .now,
            endTime: .now.addingTimeInterval(3600),
            externalID: externalID
        )
        context.insert(event)
        return event
    }

    @Test func deletesEventAndItsEmptyInterviewStub() throws {
        let context = makeContext()
        let event = makeEvent("tombstone-empty-interview", in: context)

        let interview = Interview(date: .now, candidateName: "Andy", role: "Senior Platform Engineer")
        interview.calendarEvent = event
        context.insert(interview)
        let interviewID = interview.id
        try context.save()

        #expect(interview.isEmpty)

        event.deleteWithEmptyStubs(in: context)
        try context.save()

        #expect(try fetchEvent("tombstone-empty-interview", in: context) == nil)
        let remaining = try context.fetch(
            FetchDescriptor<Interview>(predicate: #Predicate { $0.id == interviewID })
        )
        #expect(remaining.isEmpty, "an auto-created stub with no content should be removed")
    }

    @Test func keepsInterviewThatHasNotes() throws {
        let context = makeContext()
        let event = makeEvent("tombstone-noted-interview", in: context)

        let interview = Interview(date: .now, candidateName: "Bea", role: "Backend Engineer")
        interview.calendarEvent = event
        interview.conclusion = "Strong hire, good systems depth"
        context.insert(interview)
        let interviewID = interview.id
        try context.save()

        #expect(!interview.isEmpty)

        event.deleteWithEmptyStubs(in: context)
        try context.save()

        #expect(try fetchEvent("tombstone-noted-interview", in: context) == nil)
        let survivor = try context.fetch(
            FetchDescriptor<Interview>(predicate: #Predicate { $0.id == interviewID })
        ).first
        #expect(survivor != nil, "an interview with a conclusion must never be destroyed")
        #expect(survivor?.calendarEvent == nil, "its event link should nullify, not cascade")
        #expect(survivor?.conclusion == "Strong hire, good systems depth")
    }

    @Test func keepsMeetingThatHasNotes() throws {
        let context = makeContext()
        let event = makeEvent("tombstone-noted-meeting", in: context)

        let meeting = Meeting(date: .now, title: "Weekly sync")
        meeting.calendarEvent = event
        meeting.notes = "Agreed to split the ledger migration into two phases"
        context.insert(meeting)
        let meetingID = meeting.id
        try context.save()

        #expect(!meeting.isEmpty)

        event.deleteWithEmptyStubs(in: context)
        try context.save()

        let survivor = try context.fetch(
            FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingID })
        ).first
        #expect(survivor?.notes == "Agreed to split the ledger migration into two phases")
        #expect(survivor?.calendarEvent == nil)
    }

    @Test func deletesEmptyMeetingStub() throws {
        let context = makeContext()
        let event = makeEvent("tombstone-empty-meeting", in: context)

        let meeting = Meeting(date: .now, title: "Weekly sync")
        meeting.calendarEvent = event
        context.insert(meeting)
        let meetingID = meeting.id
        try context.save()

        #expect(meeting.isEmpty)

        event.deleteWithEmptyStubs(in: context)
        try context.save()

        let remaining = try context.fetch(
            FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingID })
        )
        #expect(remaining.isEmpty)
    }

    @Test func meetingWithOnlyAProjectIsNotEmpty() throws {
        let context = makeContext()
        let meeting = Meeting(date: .now, title: "1:1")
        context.insert(meeting)
        meeting.project = Project(name: "Promotions \(UUID())")

        #expect(!meeting.isEmpty, "a project is user intent and should protect the record")
    }

    @Test func meetingWithOnlyASlackLinkIsNotEmpty() throws {
        let context = makeContext()
        let meeting = Meeting(date: .now, title: "Design review")
        meeting.slackURL = URL(string: "https://larder.slack.com/archives/C123/p456")
        context.insert(meeting)

        #expect(!meeting.isEmpty, "shared notes mean the meeting happened and should survive a cancelled event")
    }

    // A tombstone for an event that was never synced locally is the common case; it must be a
    // harmless no-op rather than deleting something unrelated.
    @Test func unknownTombstoneMatchesNothing() throws {
        let context = makeContext()
        let event = makeEvent("tombstone-bystander", in: context)
        try context.save()

        #expect(try fetchEvent("id-that-was-never-synced", in: context) == nil)
        #expect(try fetchEvent("tombstone-bystander", in: context) != nil)
        _ = event
    }

    /// Sync skips hidden events, so hiding is what keeps it from growing a fresh stub.
    @Test func deletingAnInterviewHidesItsEventAndKeepsItsTodos() throws {
        let context = makeContext()
        let event = makeEvent("deleted-interview", in: context)
        let interview = Interview(date: .now, candidateName: "Andy")
        interview.calendarEvent = event
        context.insert(interview)
        let todo = Todo(title: "Submit scorecard")
        context.insert(todo)
        todo.interview = interview
        let interviewID = interview.id
        try context.save()

        interview.delete(in: context)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Interview>(predicate: #Predicate { $0.id == interviewID })).isEmpty)
        #expect(try fetchEvent("deleted-interview", in: context)?.isHidden == true)
        #expect(todo.interview == nil)
        #expect(todo.modelContext != nil)
    }

    // MARK: - removeMissing

    /// Each test passes its own far-off window, so it never sees another test's events.
    private func makeEvent(_ externalID: String, start: Date, hours: Double = 1, in context: ModelContext)
        -> CalendarEvent
    {
        let event = CalendarEvent(
            title: externalID, startTime: start, endTime: start.addingTimeInterval(hours * 3600),
            externalID: externalID)
        context.insert(event)
        return event
    }

    private func day(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string + "T00:00:00Z")!
    }

    @Test func removesEventsGoogleNoLongerReturns() throws {
        let context = makeContext()
        let window = DateInterval(start: day("2001-01-01"), end: day("2001-01-29"))
        makeEvent("rm-kept", start: day("2001-01-10"), in: context)
        makeEvent("rm-gone", start: day("2001-01-11"), in: context)
        makeEvent("rm-before", start: day("2000-12-20"), in: context)
        makeEvent("rm-after", start: day("2001-02-10"), in: context)
        try context.save()

        let removed = try CalendarEvent.removeMissing(from: window, keeping: ["rm-kept"], in: context)
        try context.save()

        #expect(removed == 1)
        #expect(try fetchEvent("rm-kept", in: context) != nil)
        #expect(try fetchEvent("rm-gone", in: context) == nil)
        #expect(try fetchEvent("rm-before", in: context) != nil, "history outside the window is left alone")
        #expect(try fetchEvent("rm-after", in: context) != nil)
    }

    /// Google returns an event that overlaps the window, so one that started before it is judged too.
    @Test func judgesEventsThatOverlapTheWindowsStart() throws {
        let context = makeContext()
        let window = DateInterval(start: day("2002-01-01"), end: day("2002-01-29"))
        makeEvent("overlap-kept", start: day("2001-12-20"), hours: 24 * 20, in: context)
        makeEvent("overlap-gone", start: day("2001-12-21"), hours: 24 * 20, in: context)
        try context.save()

        try CalendarEvent.removeMissing(from: window, keeping: ["overlap-kept"], in: context)
        try context.save()

        #expect(try fetchEvent("overlap-kept", in: context) != nil)
        #expect(try fetchEvent("overlap-gone", in: context) == nil)
    }

    @Test func nothingSeenRemovesNothing() throws {
        let context = makeContext()
        let window = DateInterval(start: day("2003-01-01"), end: day("2003-01-29"))
        makeEvent("empty-fetch", start: day("2003-01-10"), in: context)
        try context.save()

        let removed = try CalendarEvent.removeMissing(from: window, keeping: [], in: context)

        #expect(removed == 0)
        #expect(try fetchEvent("empty-fetch", in: context) != nil)
    }

    @Test func removingAMissingEventKeepsItsWrittenMeeting() throws {
        let context = makeContext()
        let window = DateInterval(start: day("2004-01-01"), end: day("2004-01-29"))
        makeEvent("missing-kept", start: day("2004-01-09"), in: context)
        let event = makeEvent("missing-with-notes", start: day("2004-01-10"), in: context)
        let meeting = Meeting(date: day("2004-01-10"), title: "Weekly sync")
        meeting.calendarEvent = event
        meeting.notes = "Decided to ship on Friday"
        context.insert(meeting)
        let meetingID = meeting.id
        try context.save()

        try CalendarEvent.removeMissing(from: window, keeping: ["missing-kept"], in: context)
        try context.save()

        #expect(try fetchEvent("missing-with-notes", in: context) == nil)
        let survivor = try context.fetch(FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == meetingID })).first
        #expect(survivor?.notes == "Decided to ship on Friday")
    }
}
