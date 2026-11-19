import Foundation
import SwiftData

/// How long one kind of record is kept. Every rule is on until the user turns it off in Settings.
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
    /// Deletes interviews with no open todo, with their calendar event and todos (`Interview.expired`).
    public var interviews: RetentionRule
    /// Deletes meetings, notes included, and events without an interview.
    public var calendarEvents: RetentionRule
    /// Deletes PRs by their last update on GitHub, and stops syncing them.
    public var pullRequests: RetentionRule

    public static let defaultDays = (interviews: 30, calendarEvents: 180, pullRequests: 365)

    public init(
        interviews: RetentionRule = RetentionRule(isEnabled: true, days: defaultDays.interviews),
        calendarEvents: RetentionRule = RetentionRule(isEnabled: true, days: defaultDays.calendarEvents),
        pullRequests: RetentionRule = RetentionRule(isEnabled: true, days: defaultDays.pullRequests)
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
    public var meetings: [Meeting] = []
    public var calendarEvents: [CalendarEvent] = []
    public var pullRequests: [PullRequest] = []

    public var isEmpty: Bool { interviews.isEmpty && meetings.isEmpty && calendarEvents.isEmpty && pullRequests.isEmpty }

    /// Finds everything first, then `remove` acts, so a dry run lists exactly what a real run removes.
    public static func find(_ settings: RetentionSettings, now: Date = .now, in context: ModelContext) throws -> ExpiredRecords {
        var expired = ExpiredRecords()
        if let cutoff = settings.interviews.cutoff(now: now) {
            expired.interviews = try Interview.expired(before: cutoff, in: context)
        }
        if let cutoff = settings.calendarEvents.cutoff(now: now) {
            expired.meetings = try Meeting.expired(before: cutoff, in: context)
            expired.calendarEvents = try CalendarEvent.expired(before: cutoff, in: context)
        }
        if let cutoff = settings.pullRequests.cutoff(now: now) {
            expired.pullRequests = try PullRequest.expired(before: cutoff, in: context)
        }
        return expired
    }

    /// Permanent: nothing goes to the Trash. Saves. PRs go first: `PullRequest.delete` fetches the
    /// todos it unlinks, and must not touch ones an interview has deleted.
    public func remove(in context: ModelContext) throws {
        for pr in pullRequests { try pr.delete(in: context) }
        for meeting in meetings { context.delete(meeting) }
        for event in calendarEvents { context.delete(event) }
        for interview in interviews { interview.deleteExpired(in: context) }
        try context.save()
    }
}

extension Interview {
    /// Past `cutoff` counting from the later of the interview and its debrief, with no open todo: an
    /// unsubmitted scorecard keeps it. A completed or trashed todo counts as closed.
    static func expired(before cutoff: Date, in context: ModelContext) throws -> [Interview] {
        try context.fetch(FetchDescriptor<Interview>(predicate: #Predicate { $0.date < cutoff }))
            .filter { max($0.date, $0.debriefDate ?? $0.date) < cutoff && !$0.hasOpenTodo }
    }

    var hasOpenTodo: Bool {
        (todos ?? []).contains { !$0.isCompleted && !$0.isTrashed }
    }

    /// Deletes the interview with its todos, all closed, and its calendar event, whose title often
    /// names the candidate. Calendar sync looks only a week back, so the event doesn't return.
    func deleteExpired(in context: ModelContext) {
        for todo in todos ?? [] { context.delete(todo) }
        if let calendarEvent { context.delete(calendarEvent) }
        context.delete(self)
    }
}

extension Meeting {
    /// Dated before `cutoff`, written in or not, with or without a calendar event. Its todos stay, unlinked.
    static func expired(before cutoff: Date, in context: ModelContext) throws -> [Meeting] {
        try context.fetch(FetchDescriptor<Meeting>(predicate: #Predicate { $0.date < cutoff }))
    }
}

extension CalendarEvent {
    /// Ended before `cutoff`, without an interview, which the interview rule decides. Its meeting
    /// started before the event ended, so it is expired too. Calendar sync looks only a week back,
    /// so these don't return.
    static func expired(before cutoff: Date, in context: ModelContext) throws -> [CalendarEvent] {
        try context.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.endTime < cutoff }))
            .filter { $0.interview == nil }
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
    public var meetings = 0
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
        counts.meetings = expired.meetings.count
        counts.calendarEvents = expired.calendarEvents.count
        counts.pullRequests = expired.pullRequests.count
        try expired.remove(in: modelContext)
        return counts
    }
}
