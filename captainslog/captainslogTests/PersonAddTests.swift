import Foundation
import SwiftData
import Testing
import CaptainsLogKit

// One shared in-memory container, tests one at a time: see PersonMergeTests. `Person.add` matches
// against everyone in the store, so each test uses its own emails and handles.
@Suite(.serialized)
@MainActor
struct PersonAddTests {
    private static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: Schema(CaptainsLogSchema.models), configurations: [config])
    }()

    private var context: ModelContext { Self.container.mainContext }

    private func unique(_ name: String) -> String {
        "\(name)\(UUID().uuidString.prefix(8))".lowercased()
    }

    @Test func addsSomeoneNewWhoIsListed() throws {
        let handle = unique("zed")
        let person = try Person.add(RosterEntry(name: " Zed Quinn ", github: "@\(handle)"), in: context).person
        #expect(person.name == "Zed Quinn")
        #expect(person.githubHandle == handle)
        #expect(person.isAddedManually)
        #expect(person.isMeaningfulContact)
    }

    @Test func matchesAnUnlistedPersonInsteadOfAddingAnother() throws {
        let email = "\(unique("jess"))@larder.co.uk"
        let unlisted = Person(name: "Jess M", email: email)
        context.insert(unlisted)
        #expect(!unlisted.isMeaningfulContact)
        let github = unique("jm")

        let person = try Person.add(RosterEntry(name: "Jess Moore", email: email.uppercased(), github: github), in: context).person

        #expect(person.id == unlisted.id)
        #expect(person.name == "Jess M")
        #expect(person.githubHandle == github)
        #expect(person.isMeaningfulContact)
        let matching = try context.fetch(FetchDescriptor<Person>()).filter { $0.email == email }
        #expect(matching.count == 1)
    }

    // The usual case: someone sync made from a calendar invite, with nothing new to fill in. Being
    // listed is the change.
    @Test func listsAnUnlistedPersonEvenWithNothingToFill() throws {
        let email = "\(unique("kim"))@larder.co.uk"
        let unlisted = Person(name: "Kim Lee", email: email)
        context.insert(unlisted)

        let (person, row) = try Person.add(RosterEntry(name: "Kim Lee", email: email), in: context)

        #expect(row.action == .update)
        #expect(row.listsInPeople)
        #expect(row.filled.isEmpty)
        #expect(person.id == unlisted.id)
        #expect(person.isMeaningfulContact)
    }

    // A name alone matches no one, so a second add makes a second person, and the namesake warns.
    @Test func warnsAboutANamesakeWhenAddingByNameAlone() throws {
        let name = unique("Robin ")
        let first = try Person.add(RosterEntry(name: name), in: context).person

        let row = try Person.planAdd(RosterEntry(name: name.uppercased()), among: context.fetch(FetchDescriptor<Person>()))

        #expect(row.action == .create)
        #expect(Person.namesakes(of: row, among: try context.fetch(FetchDescriptor<Person>())).map(\.id) == [first.id])
    }

    @Test func refusesToMatchTwoPeople() throws {
        let email = "\(unique("al"))@larder.co.uk"
        let github = unique("al")
        let first = Person(name: "Al", email: email)
        let second = Person(name: "Al P", githubHandle: github)
        context.insert(first)
        context.insert(second)

        #expect(throws: PersonAddError.matchesSeveral(["Al", "Al P"])) {
            try Person.add(RosterEntry(name: "Al Park", email: email, github: github), in: context)
        }
        #expect(!first.isAddedManually)
        #expect(!second.isAddedManually)
        #expect(second.email == nil)
    }

    @Test func rejectsAMissingNameOrABadEmail() {
        #expect(throws: PersonAddError.noName) {
            try Person.planAdd(RosterEntry(name: "  ", email: "a@x.com"), among: [])
        }
        #expect(throws: PersonAddError.invalidEmail("alice")) {
            try Person.planAdd(RosterEntry(name: "Alice", email: "alice"), among: [])
        }
    }

    @Test func mergeKeepsTheFlag() throws {
        let keep = Person(name: "Bo", githubHandle: unique("bo"))
        let duplicate = Person(name: "Bo S")
        duplicate.isAddedManually = true
        context.insert(keep)
        context.insert(duplicate)
        keep.absorb(duplicate, in: context)
        #expect(keep.isAddedManually)
    }
}
