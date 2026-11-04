import Foundation
import SwiftData
import Testing
import CaptainsLogKit

// Creating more than one SwiftData `ModelContainer` for the same models in a
// single process crashes (SIGTRAP inside SwiftData), so all tests share ONE
// in-memory container. `.serialized` runs them one at a time (Swift Testing
// parallelises by default). Tests don't reset the store between runs — each uses
// its own objects and asserts against those, scoping any lookups by id.
@Suite(.serialized)
@MainActor
struct PersonMergeTests {
    private static let container: ModelContainer = {
        let schema = Schema(CaptainsLogSchemaV1.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func makeContext() -> ModelContext {
        Self.container.mainContext
    }

    @Test func absorbReassignsRelationshipsAndDeletesOther() throws {
        let context = makeContext()

        let keep = Person(name: "Alice Park", email: "alice@larder.co.uk")
        let dup = Person(name: "alicepark", githubHandle: "alicepark")
        dup.syncsPullRequests = true
        context.insert(keep)
        context.insert(dup)

        let authored = PullRequest(number: 1, title: "Authored", url: URL(string: "https://x/1")!, repo: "r", state: .open, createdAt: .now, isAuthoredByMe: false)
        authored.author = dup
        context.insert(authored)

        let reviewed = PullRequest(number: 2, title: "Reviewed", url: URL(string: "https://x/2")!, repo: "r", state: .open, createdAt: .now, isAuthoredByMe: true)
        reviewed.reviewers = [dup]
        context.insert(reviewed)

        let meeting = Meeting(date: .now, title: "Sync")
        meeting.attendees = [dup]
        context.insert(meeting)

        let feedback = Feedback(date: .now, person: dup, content: "Nice work")
        context.insert(feedback)

        let interview = Interview(date: .now, candidateName: "Candidate")
        interview.coInterviewer = dup
        context.insert(interview)

        try context.save()

        keep.absorb(dup, in: context)
        try context.save()

        #expect(authored.author?.id == keep.id)
        #expect(reviewed.reviewers.map(\.id) == [keep.id])
        #expect(meeting.attendees.map(\.id) == [keep.id])
        #expect(feedback.person.id == keep.id)
        #expect(interview.coInterviewer?.id == keep.id)
        // absorb walks `other.interviews`, so a mis-declared inverse would silently no-op.
        #expect(keep.interviews?.map(\.id) == [interview.id])

        // Empty profile fields backfilled from the absorbed record.
        #expect(keep.githubHandle == "alicepark")
        #expect(keep.syncsPullRequests)

        // `dup` is gone, `keep` remains (scoped by id — the store is shared).
        let dupID = dup.id
        let keepID = keep.id
        let dupRemaining = try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == dupID }))
        #expect(dupRemaining.isEmpty)
        let keepRemaining = try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == keepID }))
        #expect(keepRemaining.count == 1)
    }

    @Test func absorbDoesNotDuplicateWhenBothAreOnSameRelationship() throws {
        let context = makeContext()

        let keep = Person(name: "Alice")
        let dup = Person(name: "Alice (dupe)")
        context.insert(keep)
        context.insert(dup)

        let meeting = Meeting(date: .now, title: "Sync")
        meeting.attendees = [keep, dup]
        context.insert(meeting)
        try context.save()

        keep.absorb(dup, in: context)
        try context.save()

        #expect(meeting.attendees.map(\.id) == [keep.id])
    }

    @Test func isMeaningfulContactIgnoresCalendarOnlyPeople() throws {
        let context = makeContext()

        let calendarOnly = Person(name: "vendor@example.com")
        let event = CalendarEvent(title: "Vendor", startTime: .now, endTime: .now, externalID: "e1")
        event.attendees = [calendarOnly]
        context.insert(calendarOnly)
        context.insert(event)

        let real = Person(name: "Bob")
        let meeting = Meeting(date: .now, title: "1:1")
        meeting.attendees = [real]
        context.insert(real)
        context.insert(meeting)
        try context.save()

        #expect(calendarOnly.isMeaningfulContact == false)
        #expect(real.isMeaningfulContact == true)
    }

    @Test func coInterviewerIsAMeaningfulContact() throws {
        let context = makeContext()

        let coInterviewer = Person(name: "Carol")
        let interview = Interview(date: .now, candidateName: "Dana")
        interview.coInterviewer = coInterviewer
        context.insert(coInterviewer)
        context.insert(interview)
        try context.save()

        #expect(coInterviewer.isMeaningfulContact == true)
        #expect(coInterviewer.activityScore == 1)
    }

    @Test func absorbKeepsTheSelfMark() throws {
        let context = makeContext()

        let keep = Person(name: "Me", githubHandle: "me-gh")
        let dup = Person(name: "me", email: "me@larder.co.uk")
        context.insert(keep)
        context.insert(dup)
        try dup.markAsSelf(in: context)
        try context.save()

        keep.absorb(dup, in: context)
        try context.save()

        #expect(keep.isSelf)
        #expect(try Person.me(in: context)?.id == keep.id)
    }

    @Test func markAsSelfUnmarksEveryoneElse() throws {
        let context = makeContext()

        let first = Person(name: "First")
        let second = Person(name: "Second")
        context.insert(first)
        context.insert(second)
        try first.markAsSelf(in: context)
        try context.save()

        try second.markAsSelf(in: context)
        try context.save()

        #expect(!first.isSelf)
        #expect(second.isSelf)
        #expect(try context.fetchCount(FetchDescriptor<Person>(predicate: #Predicate { $0.isSelf })) == 1)
    }
}
