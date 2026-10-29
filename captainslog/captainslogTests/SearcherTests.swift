import Foundation
import SwiftData
import Testing
import CaptainsLogKit

// One shared in-memory container for the whole suite, serialized: see PersonMergeTests for why.
// Nothing is reset between tests; each test searches for a word only its own records contain.
@Suite(.serialized)
@MainActor
struct SearcherTests {
    private static let container: ModelContainer = {
        let schema = Schema(CaptainsLogSchemaV1.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private var context: ModelContext { Self.container.mainContext }

    /// A word no other test's records contain.
    private func uniqueWord() -> String {
        "w" + UUID().uuidString.replacing("-", with: "")
    }

    private func insert(_ models: any PersistentModel...) {
        for model in models { context.insert(model) }
    }

    private func search(_ query: String) throws -> [SearchHit] {
        try Searcher.search(query, in: context)
    }

    @Test func findsLongFormTextInEveryType() throws {
        let word = uniqueWord()
        let meeting = Meeting(date: .now, title: "Sync")
        meeting.transcript = "We agreed on \(word) next quarter"
        let interview = Interview(date: .now, candidateName: "Sam")
        interview.riskFactors = "Unsure about \(word)"
        let pr = PullRequest(number: 4242, title: "Refactor", url: URL(string: "https://x/4242")!, repo: "r", state: .open, createdAt: .now, isAuthoredByMe: true)
        pr.body = "Prepares for \(word)"
        let project = Project(name: "Project \(UUID().uuidString)")
        project.notes = "Goal: \(word)"
        insert(meeting, interview, pr, project)
        try context.save()

        let hits = try search(word)
        #expect(Set(hits.map(\.kind)) == [.meeting, .interview, .pr, .project])
        #expect(hits.first { $0.kind == .meeting }?.match.field == "transcript")
        #expect(hits.first { $0.kind == .interview }?.match.field == "riskFactors")
        #expect(try search("#4242").map(\.id) == [pr.id])
    }

    @Test func feedbackAndPRsMatchTheirPersonsName() throws {
        let name = uniqueWord().capitalized
        let person = Person(name: "\(name) Okafor")
        context.insert(person)
        let feedback = Feedback(date: .now, person: person, content: "Great handover")
        context.insert(feedback)
        let pr = PullRequest(number: 1, title: "Fix", url: URL(string: "https://x/1")!, repo: "r", state: .open, createdAt: .now, isAuthoredByMe: false)
        context.insert(pr)
        pr.author = person
        try context.save()

        let hits = try search(name)
        #expect(Set(hits.map(\.kind)) == [.person, .feedback, .pr])
        #expect(hits.first { $0.kind == .feedback }?.title == "Feedback for \(name) Okafor")
        #expect(try search("\(name) handover").map(\.id) == [feedback.id])
    }

    @Test func everyWordMustMatchSomewhereInTheRecord() throws {
        let (a, b) = (uniqueWord(), uniqueWord())
        let both = LogEntry(timestamp: .now, source: .manual, title: "About \(a)", content: "and \(b)")
        let one = LogEntry(timestamp: .now, source: .manual, title: "Only \(a)", content: "")
        context.insert(both)
        context.insert(one)
        try context.save()

        #expect(try search("\(b) \(a)").map(\.id) == [both.id])
        #expect(Set(try search(a).map(\.id)) == [both.id, one.id])
    }

    @Test func leavesOutTrashedTodosAndCalendarOnlyPeople() throws {
        let word = uniqueWord()
        let kept = Todo(title: "Ask about \(word)")
        let trashed = Todo(title: "Trashed \(word)")
        trashed.trashedDate = .now
        let attendeeOnly = Person(name: "\(word) Attendee")
        insert(kept, trashed, attendeeOnly)
        try context.save()

        #expect(try search(word).map(\.id) == [kept.id])
    }

    @Test func undatedResultsComeFirstThenNewest() throws {
        let word = uniqueWord()
        let older = LogEntry(timestamp: .now.addingTimeInterval(-86_400), source: .manual, title: "Old \(word)", content: "")
        let newer = LogEntry(timestamp: .now, source: .manual, title: "New \(word)", content: "")
        let todo = Todo(title: "Open \(word)")
        let project = Project(name: "\(word) project")
        insert(older, newer, todo, project)
        try context.save()

        #expect(try search(word).map(\.id) == [project.id, todo.id, newer.id, older.id])
    }

    @Test func theActorSeesSavedRecords() async throws {
        let word = uniqueWord()
        let entry = LogEntry(timestamp: .now, source: .manual, title: word, content: "")
        context.insert(entry)
        try context.save()

        let hits = try await Searcher(modelContainer: Self.container).search(word)
        #expect(hits.map(\.id) == [entry.id])
    }
}
