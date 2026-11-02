import Foundation
import SwiftData

public enum SearchKind: String, CaseIterable, Codable, Sendable {
    case person, project, todo, log, meeting, interview, pr, feedback
}

/// One record that matched a search. Carries its id rather than the model, so it can cross actors.
public struct SearchHit: Sendable, Identifiable {
    public let kind: SearchKind
    public let id: UUID
    public let title: String
    /// Nil for people, open projects and undated open todos: they're current, so they sort first.
    public let date: Date?
    public let match: SearchMatch
    /// The record's `isPrivate`; false for types that don't have one. The CLI hides private snippets.
    public let isPrivate: Bool

    /// Undated hits first, by kind then title; then newest first.
    static func precedes(_ a: SearchHit, _ b: SearchHit) -> Bool {
        switch (a.date, b.date) {
        case let (x?, y?): return x > y
        case (nil, _?): return true
        case (_?, nil): return false
        case (nil, nil):
            let (ka, kb) = (SearchKind.allCases.firstIndex(of: a.kind)!, SearchKind.allCases.firstIndex(of: b.kind)!)
            return ka != kb ? ka < kb : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
}

/// Searches the text of every record type for all the words of a query. The app runs it off the
/// main actor; the CLI calls `search(_:in:)` directly.
@ModelActor
public actor Searcher {
    public func search(_ query: String) throws -> [SearchHit] {
        try Self.search(query, in: modelContext)
    }

    public static func search(_ query: String, in context: ModelContext) throws -> [SearchHit] {
        let terms = SearchMatch.terms(of: query)
        // SQLite narrows each type by the longest word; SearchMatch then checks every word in Swift.
        guard let q = terms.max(by: { $0.count < $1.count }) else { return [] }
        let number = terms.lazy.compactMap { Int($0.trimmingPrefix("#")) }.first ?? -1
        var hits: [SearchHit] = []

        func add(_ kind: SearchKind, _ id: UUID, _ title: String, _ date: Date?, isPrivate: Bool = false, _ fields: [(name: String, text: String?)]) {
            guard let match = SearchMatch.first(query, in: fields) else { return }
            hits.append(SearchHit(kind: kind, id: id, title: title, date: date, match: match, isPrivate: isPrivate))
        }

        for p in try context.fetch(FetchDescriptor<Person>(predicate: #Predicate {
            $0.name.localizedStandardContains(q)
                || ($0.email?.localizedStandardContains(q) ?? false)
                || ($0.slackHandle?.localizedStandardContains(q) ?? false)
                || ($0.githubHandle?.localizedStandardContains(q) ?? false)
        })) where p.isMeaningfulContact {
            add(.person, p.id, p.name, nil, [("name", p.name), ("email", p.email), ("slackHandle", p.slackHandle), ("githubHandle", p.githubHandle)])
        }

        for p in try context.fetch(FetchDescriptor<Project>(predicate: #Predicate {
            $0.name.localizedStandardContains(q) || ($0.notes?.localizedStandardContains(q) ?? false)
        })) {
            add(.project, p.id, p.name, p.completedDate, [("name", p.name), ("notes", p.notes)])
        }

        for t in try context.fetch(FetchDescriptor<Todo>(predicate: #Predicate {
            $0.trashedDate == nil
                && ($0.title.localizedStandardContains(q) || ($0.notes?.localizedStandardContains(q) ?? false))
        })) {
            add(.todo, t.id, t.title, t.completedDate ?? t.dueDate, isPrivate: t.isPrivate, [("title", t.title), ("notes", t.notes)])
        }

        for e in try context.fetch(FetchDescriptor<LogEntry>(predicate: #Predicate {
            $0.title.localizedStandardContains(q) || $0.content.localizedStandardContains(q)
        })) {
            add(.log, e.id, e.title, e.timestamp, isPrivate: e.isPrivate, [("title", e.title), ("content", e.content)])
        }

        for m in try context.fetch(FetchDescriptor<Meeting>(predicate: #Predicate {
            $0.title.localizedStandardContains(q)
                || ($0.prepNotes?.localizedStandardContains(q) ?? false)
                || ($0.notes?.localizedStandardContains(q) ?? false)
                || ($0.summary?.localizedStandardContains(q) ?? false)
                || ($0.transcript?.localizedStandardContains(q) ?? false)
        })) {
            add(.meeting, m.id, m.title, m.date, isPrivate: m.isPrivate, [
                ("title", m.title), ("summary", m.summary), ("notes", m.notes), ("prepNotes", m.prepNotes), ("transcript", m.transcript),
            ])
        }

        // Interviews are few, so match their text fields in Swift rather than in a predicate.
        for i in try context.fetch(FetchDescriptor<Interview>()) {
            add(.interview, i.id, i.candidateName, i.date, isPrivate: i.isPrivate, [
                ("candidateName", i.candidateName), ("role", i.role), ("problemName", i.problemName),
                ("conclusion", i.conclusion), ("rawNotes", i.rawNotes), ("upsides", i.upsides),
                ("riskFactors", i.riskFactors), ("levelAssessment", i.levelAssessment), ("debriefNotes", i.debriefNotes),
            ])
        }

        for pr in try context.fetch(FetchDescriptor<PullRequest>(predicate: #Predicate {
            $0.number == number
                || $0.title.localizedStandardContains(q)
                || $0.repo.localizedStandardContains(q)
                || ($0.body?.localizedStandardContains(q) ?? false)
                || ($0.notes?.localizedStandardContains(q) ?? false)
                || ($0.author?.name.localizedStandardContains(q) ?? false)
        })) {
            add(.pr, pr.id, "\(pr.repo)#\(pr.number) \(pr.title)", pr.createdAt, [
                ("title", pr.title), ("notes", pr.notes), ("body", pr.body), ("repo", pr.repo),
                ("number", "#\(pr.number)"), ("author", pr.author?.name),
            ])
        }

        for f in try context.fetch(FetchDescriptor<Feedback>(predicate: #Predicate {
            $0.content.localizedStandardContains(q) || $0.person.name.localizedStandardContains(q)
        })) {
            add(.feedback, f.id, "Feedback for \(f.person.name)", f.date, [("content", f.content), ("person", f.person.name)])
        }

        return hits.sorted(by: SearchHit.precedes)
    }
}
