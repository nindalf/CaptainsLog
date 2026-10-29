import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

extension People {
    struct Import: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Import a roster: a JSON array of {name, email, github, slack}",
            discussion: "Matches people by email, then GitHub handle, then Slack handle, and folds several matches into one (Person.absorb). Only fills empty fields; a different stored value is kept and listed under conflicts. Without --yes, prints what it would do and changes nothing."
        )

        @Argument(help: "Roster file, or - to read stdin")
        var path: String

        @Flag(name: .long, help: "Apply the import. Merged duplicates can't be brought back")
        var yes: Bool = false

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let data: Data
            if path == "-" {
                data = FileHandle.standardInput.readDataToEndOfFile()
            } else {
                do {
                    data = try Data(contentsOf: URL(fileURLWithPath: path))
                } catch {
                    throw ValidationError("Can't read \(path): \(error.localizedDescription)")
                }
            }
            let entries: [RosterEntry]
            do {
                entries = try Roster.decode(data)
            } catch let error as RosterError {
                throw ValidationError(error.localizedDescription)
            }

            let context = ModelContext(try Store.makeContainer())
            let people = try context.fetch(FetchDescriptor<Person>())
            let rows: [RosterImportRow]
            if yes {
                rows = Roster.apply(entries, to: people, in: context)
                try context.save()
            } else {
                rows = Roster.plan(entries, against: people)
            }

            try printJSON(RosterImportOutput(applied: yes, rows: rows), pretty: pretty)
        }
    }

    struct Export: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print a roster for import elsewhere",
            discussion: "By default, the people the People tab lists. People with no email or handle are left out."
        )

        @Flag(name: .long, help: "Everyone, people who are only calendar attendees included")
        var all: Bool = false

        @Flag(name: .long, help: "Only people whose PRs are synced")
        var teammates: Bool = false

        @Option(name: .long, help: "Only this person (UUID). Repeatable")
        var person: [String] = []

        func validate() throws {
            if [all, teammates, !person.isEmpty].filter({ $0 }).count > 1 {
                throw ValidationError("Only one of --all, --teammates and --person")
            }
        }

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let people: [Person]
            if !person.isEmpty {
                people = try person.map { try People.person(id: $0, in: context) }
            } else {
                people = try context.fetch(FetchDescriptor<Person>()).filter { person in
                    if all { return true }
                    if teammates { return person.syncsPullRequests }
                    return person.isMeaningfulContact
                }
            }
            let data = try Roster.encode(Roster.entries(for: people))
            print(String(decoding: data, as: UTF8.self))
        }
    }
}

private struct RosterImportOutput: Encodable {
    let applied: Bool
    let counts: [String: Int]
    let rows: [RosterImportRow]

    init(applied: Bool, rows: [RosterImportRow]) {
        self.applied = applied
        self.rows = rows
        var counts = Dictionary(grouping: rows, by: \.action.rawValue).mapValues(\.count)
        counts["merged"] = rows.map(\.merged.count).reduce(0, +)
        counts["conflicts"] = rows.map(\.conflicts.count).reduce(0, +)
        self.counts = counts
    }
}
