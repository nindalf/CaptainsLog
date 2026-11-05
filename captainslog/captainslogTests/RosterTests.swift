import Foundation
import SwiftData
import Testing
import CaptainsLogKit

// One shared in-memory container, tests one at a time: see PersonMergeTests. Planning
// takes the people to match against, so tests pass their own and never see each other's.
@Suite(.serialized)
@MainActor
struct RosterTests {
    private static let container: ModelContainer = {
        let schema = Schema(CaptainsLogSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private var context: ModelContext { Self.container.mainContext }

    private func decode(_ json: String) throws -> [RosterEntry] {
        try Roster.decode(Data(json.utf8))
    }

    // MARK: - File

    @Test func decodeCleansValues() throws {
        let entries = try decode(#"""
            [{"name": " Alice Park ", "email": " Alice@Larder.co.uk", "github": "@alicepark", "slack": "", "team": "ignored"}]
            """#)
        #expect(entries == [RosterEntry(name: "Alice Park", email: "alice@larder.co.uk", github: "alicepark")])
    }

    @Test func decodeRejectsBadRows() {
        #expect(throws: RosterError.invalidRow(1, "no name")) {
            try decode(#"[{"name": " ", "email": "a@x.com"}]"#)
        }
        #expect(throws: RosterError.invalidRow(2, "Bo has no email, GitHub or Slack handle")) {
            try decode(#"[{"name": "Al", "email": "a@x.com"}, {"name": "Bo", "slack": "@"}]"#)
        }
        #expect(throws: RosterError.invalidRow(1, "alice isn't an email address")) {
            try decode(#"[{"name": "Al", "email": "alice"}]"#)
        }
        #expect(throws: RosterError.duplicate(field: .github, value: "Bo", rows: [1, 2])) {
            try decode(#"[{"name": "Al", "github": "bo"}, {"name": "Bo", "github": "Bo"}]"#)
        }
        #expect(throws: RosterError.self) { try decode(#"{"name": "Al"}"#) }
    }

    @Test func exportRoundTrips() throws {
        let people = [
            Person(name: "Zed", githubHandle: "zed"),
            Person(name: "Alice Park", email: "alice@larder.co.uk", slackHandle: "alice"),
            Person(name: "No Handles"),
        ]
        let entries = Roster.entries(for: people)
        #expect(entries.map(\.name) == ["Alice Park", "Zed"])
        #expect(try Roster.decode(Roster.encode(entries)) == entries)
    }

    // MARK: - Planning

    @Test func unmatchedRowCreates() throws {
        let rows = Roster.plan(try decode(#"[{"name": "New", "email": "new@x.com"}]"#), against: [])
        #expect(rows.map(\.action) == [.create])
        #expect(rows[0].personID == nil)
    }

    @Test func fillsEmptyFieldsAndPlaceholderName() throws {
        // As calendar sync creates them: named after the email's local part.
        let alice = Person(name: "alice.park", email: "alice.park@larder.co.uk")
        let rows = Roster.plan(
            try decode(#"[{"name": "Alice Park", "email": "ALICE.PARK@larder.co.uk", "github": "alicepark"}]"#),
            against: [alice]
        )
        #expect(rows[0].action == .update)
        #expect(rows[0].personID == alice.id)
        #expect(Set(rows[0].filled) == [
            RosterFieldValue(field: .name, value: "Alice Park"),
            RosterFieldValue(field: .github, value: "alicepark"),
        ])
        #expect(rows[0].conflicts.isEmpty)
        // Planning changes nothing.
        #expect(alice.name == "alice.park" && alice.githubHandle == nil)
    }

    @Test func keepsStoredValuesAndReportsConflicts() throws {
        let bob = Person(name: "Bob Jones", email: "bob@larder.co.uk", slackHandle: "bob")
        let rows = Roster.plan(
            try decode(#"[{"name": "Robert Jones", "email": "bob@larder.co.uk", "slack": "bobj"}]"#),
            against: [bob]
        )
        #expect(rows[0].action == .unchanged)
        #expect(Set(rows[0].conflicts) == [
            RosterConflict(field: .name, stored: "Bob Jones", roster: "Robert Jones"),
            RosterConflict(field: .slack, stored: "bob", roster: "bobj"),
        ])
    }

    @Test func rowMatchingAnEarlierRowsPersonIsSkipped() throws {
        let cat = Person(name: "Cat", email: "cat@larder.co.uk", githubHandle: "cat")
        let rows = Roster.plan(
            try decode(#"[{"name": "Cat", "email": "cat@larder.co.uk"}, {"name": "Other", "github": "CAT"}]"#),
            against: [cat]
        )
        #expect(rows.map(\.action) == [.unchanged, .skip])
        #expect(rows[1].skipReason == "Matches Cat, already matched by row 1")
    }

    // MARK: - Import

    @Test func applyFoldsMatchesIntoTheEmailMatch() throws {
        let byEmail = Person(name: "dana", email: "dana@larder.co.uk")
        let byGitHub = Person(name: "DanaK", githubHandle: "DanaK")
        let bySlack = Person(name: "dana.k", slackHandle: "dana.k")
        for person in [byEmail, byGitHub, bySlack] { context.insert(person) }
        let meeting = Meeting(date: .now, title: "1:1")
        meeting.attendees = [byEmail, byGitHub, bySlack]
        context.insert(meeting)
        let pr = PullRequest(number: 9, title: "PR", url: URL(string: "https://x/9")!, repo: "roster", state: .open, createdAt: .now, isAuthoredByMe: false)
        pr.author = byGitHub
        context.insert(pr)
        try context.save()

        let entries = try decode(#"[{"name": "Dana Kim", "email": "dana@larder.co.uk", "github": "danak", "slack": "dana.k"}]"#)
        let rows = Roster.apply(entries, to: [byEmail, byGitHub, bySlack], in: context)
        try context.save()

        #expect(rows[0].action == .update)
        #expect(rows[0].merged.map(\.id) == [byGitHub.id, bySlack.id])
        #expect(rows[0].filled == [RosterFieldValue(field: .name, value: "Dana Kim")])
        #expect(byEmail.name == "Dana Kim")
        #expect(byEmail.githubHandle == "DanaK")
        #expect(byEmail.slackHandle == "dana.k")
        #expect(meeting.attendees.map(\.id) == [byEmail.id])
        #expect(pr.author?.id == byEmail.id)

        let ids = [byGitHub.id, bySlack.id]
        let left = try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { ids.contains($0.id) }))
        #expect(left.isEmpty)
    }

    @Test func applyCreatesPeople() throws {
        let entries = try decode(#"[{"name": "Eve Stone", "email": "eve.roster@larder.co.uk", "github": "evestone"}]"#)
        let rows = Roster.apply(entries, to: [], in: context)
        try context.save()

        let id = try #require(rows[0].personID)
        let eve = try #require(try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })).first)
        #expect(eve.name == "Eve Stone")
        #expect(eve.email == "eve.roster@larder.co.uk")
        #expect(eve.githubHandle == "evestone")
    }
}
