import Foundation
import SwiftData

/// One person in a roster file: a JSON array of these, shared so a colleague's store
/// starts with the team's emails and handles joined up.
public struct RosterEntry: Codable, Sendable, Hashable {
    public var name: String
    public var email: String?
    public var github: String?
    public var slack: String?

    public init(name: String, email: String? = nil, github: String? = nil, slack: String? = nil) {
        self.name = name
        self.email = email
        self.github = github
        self.slack = slack
    }
}

public enum RosterField: String, Codable, Sendable, CaseIterable {
    case name, email, github, slack
}

public struct RosterFieldValue: Codable, Sendable, Hashable {
    public let field: RosterField
    public let value: String

    public init(field: RosterField, value: String) {
        self.field = field
        self.value = value
    }
}

/// A roster value that differs from the stored one. The stored one is kept.
public struct RosterConflict: Codable, Sendable, Hashable {
    public let field: RosterField
    public let stored: String
    public let roster: String

    public init(field: RosterField, stored: String, roster: String) {
        self.field = field
        self.stored = stored
        self.roster = roster
    }
}

public struct RosterMergedPerson: Codable, Sendable, Hashable {
    public let id: UUID
    public let name: String
}

/// What importing one roster row does, or did.
public struct RosterImportRow: Codable, Sendable, Identifiable {
    public enum Action: String, Codable, Sendable {
        case create, update, unchanged, skip
    }

    /// 1-based position in the roster.
    public let row: Int
    public let entry: RosterEntry
    public let action: Action
    /// The person kept. Nil for a preview's `create`, and for `skip`.
    public internal(set) var personID: UUID?
    public let personName: String?
    /// Duplicates folded into the person kept (`Person.absorb`).
    public let merged: [RosterMergedPerson]
    public let filled: [RosterFieldValue]
    public let conflicts: [RosterConflict]
    public let skipReason: String?

    public var id: Int { row }
}

public enum RosterError: LocalizedError, Equatable {
    case unreadable(String)
    case invalidRow(Int, String)
    case duplicate(field: RosterField, value: String, rows: [Int])

    public var errorDescription: String? {
        switch self {
        case .unreadable(let detail):
            "Not a roster: \(detail.trimmingCharacters(in: CharacterSet(charactersIn: "."))). Expected a JSON array of {name, email, github, slack}."
        case .invalidRow(let row, let detail):
            "Row \(row): \(detail)"
        case .duplicate(let field, let value, let rows):
            "Rows \(rows.map(String.init).joined(separator: " and ")) share the \(field.rawValue) \(value)"
        }
    }
}

public enum Roster {
    // MARK: - File

    /// Parses and cleans a roster: trims every value, drops a leading `@` from handles,
    /// lowercases emails and treats empty values as missing. Throws on a row without a
    /// name or without any of email, GitHub and Slack, and on two rows sharing a value.
    public static func decode(_ data: Data) throws -> [RosterEntry] {
        let raw: [RosterEntry]
        do {
            raw = try JSONDecoder().decode([RosterEntry].self, from: data)
        } catch let error as DecodingError {
            throw RosterError.unreadable(describe(error))
        }

        let entries = raw.map { entry in
            RosterEntry(
                name: entry.name.trimmingCharacters(in: .whitespacesAndNewlines),
                email: cleaned(entry.email)?.lowercased(),
                github: cleaned(entry.github, handle: true),
                slack: cleaned(entry.slack, handle: true)
            )
        }

        var seen: [RosterField: [String: Int]] = [:]
        for (index, entry) in entries.enumerated() {
            let row = index + 1
            if entry.name.isEmpty {
                throw RosterError.invalidRow(row, "no name")
            }
            if entry.email == nil && entry.github == nil && entry.slack == nil {
                throw RosterError.invalidRow(row, "\(entry.name) has no email, GitHub or Slack handle")
            }
            if let email = entry.email, !email.contains("@") {
                throw RosterError.invalidRow(row, "\(email) isn't an email address")
            }
            for (field, value) in identifiers(of: entry) {
                let key = value.lowercased()
                if let earlier = seen[field]?[key] {
                    throw RosterError.duplicate(field: field, value: value, rows: [earlier, row])
                }
                seen[field, default: [:]][key] = row
            }
        }
        return entries
    }

    public static func encode(_ entries: [RosterEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(entries)
    }

    /// Roster rows for these people, by name. People with no email or handle are left out:
    /// a row needs something to match on.
    public static func entries(for people: [Person]) -> [RosterEntry] {
        people
            .filter { $0.email != nil || $0.githubHandle != nil || $0.slackHandle != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { RosterEntry(name: $0.name, email: $0.email, github: $0.githubHandle, slack: $0.slackHandle) }
    }

    // MARK: - Import

    /// What importing `entries` over `people` would do, without changing anything.
    public static func plan(_ entries: [RosterEntry], against people: [Person]) -> [RosterImportRow] {
        steps(entries, against: people).map(\.row)
    }

    /// Imports `entries`: a row matches people by email, then GitHub handle, then Slack
    /// handle, ignoring case. Several matches are folded into the first (`Person.absorb`).
    /// Only empty fields are filled; a placeholder name (a handle, or an email's local part,
    /// as sync creates) counts as empty. A row matching someone an earlier row matched is
    /// skipped. `people` should be everyone in `context`. The caller saves.
    @discardableResult
    public static func apply(
        _ entries: [RosterEntry], to people: [Person], in context: ModelContext
    ) -> [RosterImportRow] {
        steps(entries, against: people).map { step in
            var row = step.row
            switch row.action {
            case .create:
                let person = Person(
                    name: step.entry.name,
                    email: step.entry.email,
                    slackHandle: step.entry.slack,
                    githubHandle: step.entry.github
                )
                context.insert(person)
                row.personID = person.id
            case .update:
                guard let keep = step.keep else { break }
                for duplicate in step.duplicates {
                    keep.absorb(duplicate, in: context)
                }
                for fill in row.filled {
                    switch fill.field {
                    case .name: keep.name = fill.value
                    case .email: keep.email = fill.value
                    case .github: keep.githubHandle = fill.value
                    case .slack: keep.slackHandle = fill.value
                    }
                }
            case .unchanged, .skip:
                break
            }
            return row
        }
    }

    // MARK: - Planning

    private struct Step {
        let entry: RosterEntry
        let row: RosterImportRow
        let keep: Person?
        let duplicates: [Person]
    }

    private static func steps(_ entries: [RosterEntry], against people: [Person]) -> [Step] {
        var index: [RosterField: [String: [Person]]] = [:]
        for person in people {
            for (field, value) in identifiers(of: person) {
                index[field, default: [:]][value.lowercased(), default: []].append(person)
            }
        }

        // Person ID to the row that matched them.
        var claimed: [UUID: Int] = [:]
        return entries.enumerated().map { offset, entry in
            let rowNumber = offset + 1
            var matches: [Person] = []
            for (field, value) in identifiers(of: entry) {
                for person in index[field]?[value.lowercased()] ?? [] where !matches.contains(where: { $0.id == person.id }) {
                    matches.append(person)
                }
            }

            if let taken = matches.first(where: { claimed[$0.id] != nil }), let earlier = claimed[taken.id] {
                return Step(
                    entry: entry,
                    row: RosterImportRow(
                        row: rowNumber, entry: entry, action: .skip, personID: nil, personName: taken.name,
                        merged: [], filled: [], conflicts: [],
                        skipReason: "Matches \(taken.name), already matched by row \(earlier)"
                    ),
                    keep: nil, duplicates: []
                )
            }
            for person in matches { claimed[person.id] = rowNumber }

            guard let keep = matches.first else {
                return Step(
                    entry: entry,
                    row: RosterImportRow(
                        row: rowNumber, entry: entry, action: .create, personID: nil, personName: entry.name,
                        merged: [], filled: [], conflicts: [], skipReason: nil
                    ),
                    keep: nil, duplicates: []
                )
            }
            let duplicates = Array(matches.dropFirst())

            // The kept person's fields once the duplicates are absorbed, which fills empty ones.
            var stored: [RosterField: String] = [:]
            for person in matches {
                for (field, value) in identifiers(of: person) where stored[field] == nil {
                    stored[field] = value
                }
            }

            var filled: [RosterFieldValue] = []
            var conflicts: [RosterConflict] = []
            if keep.name != entry.name {
                if isPlaceholderName(keep.name, identifiers: stored) {
                    filled.append(RosterFieldValue(field: .name, value: entry.name))
                } else if keep.name.caseInsensitiveCompare(entry.name) != .orderedSame {
                    conflicts.append(RosterConflict(field: .name, stored: keep.name, roster: entry.name))
                }
            }
            for (field, value) in identifiers(of: entry) {
                if let current = stored[field] {
                    if current.caseInsensitiveCompare(value) != .orderedSame {
                        conflicts.append(RosterConflict(field: field, stored: current, roster: value))
                    }
                } else {
                    filled.append(RosterFieldValue(field: field, value: value))
                }
            }

            let action: RosterImportRow.Action = duplicates.isEmpty && filled.isEmpty ? .unchanged : .update
            return Step(
                entry: entry,
                row: RosterImportRow(
                    row: rowNumber, entry: entry, action: action, personID: keep.id, personName: keep.name,
                    merged: duplicates.map { RosterMergedPerson(id: $0.id, name: $0.name) },
                    filled: filled, conflicts: conflicts, skipReason: nil
                ),
                keep: keep, duplicates: duplicates
            )
        }
    }

    /// Sync names a person after what it knows: a GitHub login, or an email's local part.
    private static func isPlaceholderName(_ name: String, identifiers: [RosterField: String]) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return true }
        var placeholders = Array(identifiers.values)
        if let email = identifiers[.email], let local = email.split(separator: "@").first {
            placeholders.append(String(local))
        }
        return placeholders.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func identifiers(of entry: RosterEntry) -> [(RosterField, String)] {
        [(.email, entry.email), (.github, entry.github), (.slack, entry.slack)]
            .compactMap { field, value in value.map { (field, $0) } }
    }

    private static func identifiers(of person: Person) -> [(RosterField, String)] {
        [(.email, person.email), (.github, person.githubHandle), (.slack, person.slackHandle)]
            .compactMap { field, value in value.map { (field, $0) } }
    }

    private static func cleaned(_ value: String?, handle: Bool = false) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if handle, value.hasPrefix("@") { value.removeFirst() }
        return value.isEmpty ? nil : value
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            "\(path(context.codingPath)) is missing \(key.stringValue)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            "\(path(context.codingPath)): \(context.debugDescription)"
        case .dataCorrupted(let context):
            context.debugDescription
        @unknown default:
            error.localizedDescription
        }
    }

    private static func path(_ codingPath: [CodingKey]) -> String {
        guard let first = codingPath.first, let index = first.intValue else { return "The file" }
        let rest = codingPath.dropFirst().map(\.stringValue)
        return (["Row \(index + 1)"] + rest).joined(separator: ".")
    }
}
