import Foundation
import SwiftData

public enum PersonAddError: LocalizedError, Equatable {
    case noName
    case invalidEmail(String)
    /// The email and handles match more than one person.
    case matchesSeveral([String])

    public var errorDescription: String? {
        switch self {
        case .noName: "A person needs a name."
        case .invalidEmail(let email): "\(email) isn't an email address."
        case .matchesSeveral(let names): "That matches \(names.joined(separator: " and ")). Merge them first."
        }
    }
}

extension Person {
    /// What `add(_:in:)` would do with `entry`: a roster import of one row, with the same matching
    /// and filling, except that a name alone will do. Throws what `add` would. `people` should be
    /// everyone in the store.
    public static func planAdd(_ entry: RosterEntry, among people: [Person]) throws -> RosterImportRow {
        let entry = Roster.cleaned(entry)
        if entry.name.isEmpty { throw PersonAddError.noName }
        if let email = entry.email, !email.contains("@") { throw PersonAddError.invalidEmail(email) }
        let row = Roster.plan([entry], against: people)[0]
        if !row.merged.isEmpty {
            throw PersonAddError.matchesSeveral([row.personName].compactMap { $0 } + row.merged.map(\.name))
        }
        return row
    }

    /// People already listed under the name a planned add would create, worth a warning: an add
    /// matches by email and handles only, so a name alone never finds anyone.
    public static func namesakes(of row: RosterImportRow, among people: [Person]) -> [Person] {
        guard row.action == .create else { return [] }
        return people.filter {
            $0.isMeaningfulContact && $0.name.caseInsensitiveCompare(row.entry.name) == .orderedSame
        }
    }

    /// Adds a person by hand: imports `entry` as a roster row (`Roster.apply`), so the People tab
    /// lists whoever it creates or matches. The caller saves.
    @discardableResult
    public static func add(_ entry: RosterEntry, in context: ModelContext) throws -> (person: Person, row: RosterImportRow) {
        let people = try context.fetch(FetchDescriptor<Person>())
        let row = try Roster.apply([planAdd(entry, among: people).entry], to: people, in: context)[0]
        guard let id = row.personID, let person = try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })).first else {
            preconditionFailure("A one-row import always keeps a person")
        }
        return (person, row)
    }
}
