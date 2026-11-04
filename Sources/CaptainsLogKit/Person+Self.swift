import Foundation
import SwiftData

/// A person who might be the app's user, and the evidence for it.
public struct SelfCandidate {
    public let person: Person
    public let reason: String
}

extension Person {
    /// The person marked as the app's user, if anyone is.
    public static func me(in context: ModelContext) throws -> Person? {
        try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.isSelf })).first
    }

    /// Marks this person as the app's user and clears the mark from anyone else.
    public func markAsSelf(in context: ModelContext) throws {
        for other in try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.isSelf }))
        where other.id != id {
            other.isSelf = false
        }
        isSelf = true
    }

    /// Guesses at the app's user from what sync saw: the author of my PRs, then whoever is on
    /// the most calendar events, since I'm on every event I sync.
    public static func selfCandidates(in context: ModelContext, limit: Int = 5) throws -> [SelfCandidate] {
        var candidates: [SelfCandidate] = []
        var seen: Set<UUID> = []

        let myPRs = try context.fetch(FetchDescriptor<PullRequest>(predicate: #Predicate { $0.isAuthoredByMe }))
        var prCounts: [UUID: (Person, Int)] = [:]
        for pr in myPRs {
            guard let author = pr.author else { continue }
            prCounts[author.id, default: (author, 0)].1 += 1
        }
        for (person, count) in prCounts.values.sorted(by: { $0.1 > $1.1 }) {
            var reason = "Author of \(count) of my \(myPRs.count) PRs"
            let events = (person.calendarEvents ?? []).count
            if events > 0 { reason += ", on \(events) calendar events" }
            candidates.append(SelfCandidate(person: person, reason: reason))
            seen.insert(person.id)
        }

        let attendees = try context.fetch(FetchDescriptor<Person>())
            .map { ($0, ($0.calendarEvents ?? []).count) }
            .filter { $0.1 > 0 && !seen.contains($0.0.id) }
            .sorted { $0.1 > $1.1 }
        for (person, count) in attendees.prefix(max(0, limit - candidates.count)) {
            candidates.append(SelfCandidate(person: person, reason: "On \(count) calendar events"))
        }
        return Array(candidates.prefix(limit))
    }
}
