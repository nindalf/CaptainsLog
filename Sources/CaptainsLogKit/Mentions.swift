import Foundation
import SwiftData

/// Who the `@` tags in a piece of text name. A tag matches a person's Slack handle, GitHub handle
/// or full name, case-insensitively, since completion inserts the Slack handle and falls back to
/// the name. The longest match wins, so `@Alice Smith` beats someone named Alice; a handle beats a
/// name of the same length. A tag that matches nobody stays plain text.
public enum Mentions {
    public static func people(in text: String, among people: [Person]) -> [Person] {
        let characters = Array(text)
        let keyed = people.map { person in
            (person, [person.slackHandle, person.githubHandle, person.name].map(normalizedKey))
        }
        var found: [Person] = []
        var seen: Set<UUID> = []
        for index in characters.indices where characters[index] == "@" {
            // The tag must start a word, so `james.kirk@larder.co.uk` is inert.
            if index > 0, isWordCharacter(characters[index - 1]) { continue }
            let rest = characters[(index + 1)...]
            var best: (length: Int, rank: Int) = (0, Int.max)
            var winners: [Person] = []
            for (person, keys) in keyed {
                for (rank, key) in keys.enumerated() {
                    guard let key, tag(at: rest, startsWith: key) else { continue }
                    let candidate = (length: key.count, rank: rank)
                    if candidate.length > best.length || (candidate.length == best.length && candidate.rank < best.rank) {
                        best = candidate
                        winners = [person]
                    } else if candidate == best, !winners.contains(where: { $0 === person }) {
                        // Duplicates with the same name or handle all count.
                        winners.append(person)
                    }
                }
            }
            for person in winners where seen.insert(person.id).inserted {
                found.append(person)
            }
        }
        return found
    }

    private static func normalizedKey(_ key: String?) -> [Character]? {
        guard let trimmed = key?.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@")), !trimmed.isEmpty else { return nil }
        return Array(trimmed.lowercased())
    }

    /// Whether `text` starts with `key` and the tag ends there. A full stop ends a tag only when no
    /// letter follows, so `@alice.smith` doesn't tag `alice`.
    private static func tag(at text: ArraySlice<Character>, startsWith key: [Character]) -> Bool {
        guard text.count >= key.count else { return false }
        var position = text.startIndex
        for character in key {
            guard text[position].lowercased() == String(character) else { return false }
            position += 1
        }
        guard position < text.endIndex else { return true }
        let next = text[position]
        if next == "." {
            let after = position + 1
            return after == text.endIndex || !isWordCharacter(text[after])
        }
        return !isWordCharacter(next) && next != "-"
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}

/// A record whose `@` tags decide who it is linked to: the text is the truth, so deleting a tag
/// unlinks. Relink when an edit ends, not per keystroke.
public protocol MentionsPeople: AnyObject {
    var people: [Person] { get set }
    /// The title and body whose tags count.
    var mentionText: String { get }
}

extension MentionsPeople {
    /// Links the record to exactly the people its text tags. Returns whether the links changed.
    /// Call only on an inserted record: relating an unsaved draft to a saved person inserts the
    /// draft.
    @discardableResult
    public func linkMentionedPeople(among candidates: [Person]) -> Bool {
        let mentioned = Mentions.people(in: mentionText, among: candidates)
        guard Set(mentioned.map(\.id)) != Set(people.map(\.id)) else { return false }
        people = mentioned
        return true
    }

    @discardableResult
    public func linkMentionedPeople(in context: ModelContext) throws -> Bool {
        // Skip the fetch when there is nothing to match and nothing to unlink.
        guard mentionText.contains("@") || !people.isEmpty else { return false }
        return linkMentionedPeople(among: try context.fetch(FetchDescriptor<Person>()))
    }
}

extension Todo: MentionsPeople {
    public var mentionText: String { [title, notes ?? ""].joined(separator: "\n") }
}

extension LogEntry: MentionsPeople {
    public var mentionText: String { [title, content].joined(separator: "\n") }
}
