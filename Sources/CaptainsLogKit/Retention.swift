import Foundation
import SwiftData

/// How long one kind of record is kept. Every rule is off until the user turns it on in Settings.
public struct RetentionRule: Equatable, Sendable {
    public var isEnabled: Bool
    public var days: Int

    public static let dayChoices = [30, 90, 180, 365]

    public init(isEnabled: Bool, days: Int) {
        self.isEnabled = isEnabled
        self.days = days
    }

    /// Records older than this go. Nil while the rule is off.
    public func cutoff(now: Date = .now) -> Date? {
        guard isEnabled else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: now)
    }
}

public struct RetentionSettings: Equatable, Sendable {
    /// Clears what was written about the candidate (`Interview.clearExpiringText`).
    public var interviews: RetentionRule
    /// Deletes events with no written meeting and no interview.
    public var calendarEvents: RetentionRule
    /// Deletes PRs by their last update on GitHub, and stops syncing them.
    public var pullRequests: RetentionRule

    public static let defaultDays = (interviews: 30, calendarEvents: 180, pullRequests: 365)

    public init(
        interviews: RetentionRule = RetentionRule(isEnabled: false, days: defaultDays.interviews),
        calendarEvents: RetentionRule = RetentionRule(isEnabled: false, days: defaultDays.calendarEvents),
        pullRequests: RetentionRule = RetentionRule(isEnabled: false, days: defaultDays.pullRequests)
    ) {
        self.interviews = interviews
        self.calendarEvents = calendarEvents
        self.pullRequests = pullRequests
    }

    public var isAnyEnabled: Bool {
        interviews.isEnabled || calendarEvents.isEnabled || pullRequests.isEnabled
    }
}

/// The records past their retention. The app's hourly loop removes them (`RetentionPruner`), and
/// `captains-log prune` lists or removes them.
public struct ExpiredRecords {
    public var interviews: [Interview] = []
    public var calendarEvents: [CalendarEvent] = []
    public var pullRequests: [PullRequest] = []

    public var isEmpty: Bool { interviews.isEmpty && calendarEvents.isEmpty && pullRequests.isEmpty }

    /// Finds everything first, then `remove` acts, so a dry run lists exactly what a real run removes.
    public static func find(_ settings: RetentionSettings, now: Date = .now, in context: ModelContext) throws -> ExpiredRecords {
        var expired = ExpiredRecords()
        if let cutoff = settings.interviews.cutoff(now: now) {
            expired.interviews = try Interview.expired(before: cutoff, in: context)
        }
        if let cutoff = settings.calendarEvents.cutoff(now: now) {
            expired.calendarEvents = try CalendarEvent.expired(before: cutoff, in: context)
        }
        if let cutoff = settings.pullRequests.cutoff(now: now) {
            expired.pullRequests = try PullRequest.expired(before: cutoff, in: context)
        }
        return expired
    }

    /// Permanent: nothing goes to the Trash. Saves.
    public func remove(in context: ModelContext) throws {
        for interview in interviews { interview.clearExpiringText() }
        for event in calendarEvents { event.deleteWithEmptyStubs(in: context) }
        for pr in pullRequests { try pr.delete(in: context) }
        try context.save()
    }
}

extension Interview {
    /// Past `cutoff` counting from the later of the interview and its debrief, with text left to clear.
    static func expired(before cutoff: Date, in context: ModelContext) throws -> [Interview] {
        try context.fetch(FetchDescriptor<Interview>(predicate: #Predicate { $0.date < cutoff }))
            .filter { max($0.date, $0.debriefDate ?? $0.date) < cutoff && $0.hasExpiringText }
    }

    var hasExpiringText: Bool {
        ![rawNotes, upsides, riskFactors, conclusion, debriefNotes, whiteboardLink].allSatisfy { $0?.isEmpty ?? true }
    }

    /// Clears what was written about the candidate. The record stays, with the candidate's name, role,
    /// problem, level and decision, so links and the scorecard todo still resolve.
    public func clearExpiringText() {
        rawNotes = nil
        upsides = nil
        riskFactors = nil
        conclusion = nil
        debriefNotes = nil
        whiteboardLink = nil
    }
}

extension CalendarEvent {
    /// Ended before `cutoff`, with no written meeting. Events with an interview stay whatever it holds:
    /// clearing an interview's text can leave it looking like an empty stub, and the interview's own
    /// rule decides what happens to it. Calendar sync looks only a week back, so these don't return.
    static func expired(before cutoff: Date, in context: ModelContext) throws -> [CalendarEvent] {
        try context.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.endTime < cutoff }))
            .filter { $0.interview == nil && ($0.meeting?.isEmpty ?? true) }
    }
}

extension PullRequest {
    /// The last update on GitHub, falling back for PRs synced before `updatedAt` was stored.
    public var lastActivity: Date { updatedAt ?? mergedAt ?? createdAt }

    /// Last updated before `cutoff`, whether linked or not. Sync skips the same PRs, so they don't return.
    static func expired(before cutoff: Date, in context: ModelContext) throws -> [PullRequest] {
        // `lastActivity` is never before `createdAt`, so this narrows the fetch without missing any.
        try context.fetch(FetchDescriptor<PullRequest>(predicate: #Predicate { $0.createdAt < cutoff }))
            .filter { $0.lastActivity < cutoff }
    }

    /// Deletes the PR for good. `Todo.pullRequest` has no inverse to nullify, so linked todos are unlinked by hand.
    public func delete(in context: ModelContext) throws {
        let id = self.id
        let todos = try context.fetch(FetchDescriptor<Todo>(predicate: #Predicate { $0.pullRequest?.id == id }))
        for todo in todos { todo.pullRequest = nil }
        context.delete(self)
    }
}

public struct RetentionCounts: Sendable {
    public var interviews = 0
    public var calendarEvents = 0
    public var pullRequests = 0

    public init() {}
}

/// Runs the retention rules off the main actor for the app's hourly loop.
@ModelActor
public actor RetentionPruner {
    public func prune(_ settings: RetentionSettings) throws -> RetentionCounts {
        let expired = try ExpiredRecords.find(settings, in: modelContext)
        var counts = RetentionCounts()
        guard !expired.isEmpty else { return counts }
        counts.interviews = expired.interviews.count
        counts.calendarEvents = expired.calendarEvents.count
        counts.pullRequests = expired.pullRequests.count
        try expired.remove(in: modelContext)
        return counts
    }
}
