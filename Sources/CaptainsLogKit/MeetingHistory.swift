import Foundation
import SwiftData

extension CalendarEvent {
    /// The recurring series this event is an instance of, read from its Google id: an instance's id
    /// is the series id plus `_` and its original start, which survives the instance being moved.
    /// Editing "this and following" splits a series, giving the new half an `_R<start>` series id,
    /// but its instances keep the original prefix, so both halves share this value.
    public var seriesID: String? {
        guard let match = externalID.firstMatch(of: #/_\d{8}(T\d{6}Z)?$/#) else { return nil }
        let id = externalID[..<match.range.lowerBound]
        return id.isEmpty ? nil : String(id)
    }
}

/// The todos a meeting's page lists beyond those filed in it.
public enum MeetingTodos {
    /// Open todos tagging any of `people`, leaving out those in `excluding`, in `open`'s order.
    public static func tagging(_ people: Set<UUID>, among open: [Todo], excluding: Set<UUID> = []) -> [Todo] {
        guard !people.isEmpty else { return [] }
        return open.filter { todo in
            !todo.isCompleted && !todo.isTrashed && !excluding.contains(todo.id)
                && todo.people.contains { people.contains($0.id) }
        }
    }
}

extension Meeting {
    public enum PreviousMatch: String, Sendable {
        /// An earlier instance of the same recurring calendar event.
        case series
        /// Mostly the same people.
        case attendees
    }

    /// The other meetings in this one's recurring series, earlier or later, oldest first. Empty for
    /// a one-off meeting.
    public func seriesMeetings(among candidates: [Meeting]) -> [Meeting] {
        guard let series = calendarEvent?.seriesID else { return [] }
        return Meeting.inSeries(series, among: candidates).filter { $0.id != id }
    }

    /// `seriesMeetings` over the whole store.
    public func seriesMeetings(in context: ModelContext) throws -> [Meeting] {
        guard calendarEvent?.seriesID != nil else { return [] }
        return seriesMeetings(among: try context.fetch(FetchDescriptor<Meeting>()))
    }

    /// The earlier events of this meeting's recurring series, newest first, whether or not they
    /// have notes: the series history its page lists. Hidden events only with a meeting.
    public func earlierSeriesEvents(among events: [CalendarEvent]) -> [CalendarEvent] {
        guard let event = calendarEvent, let series = event.seriesID else { return [] }
        return events
            .filter { other in
                other.id != event.id && other.startTime < event.startTime && other.seriesID == series
                    && (!other.isHidden || other.meeting != nil)
            }
            .sorted { $0.startTime > $1.startTime }
    }

    /// The meetings of `series` among `candidates`, oldest first.
    public static func inSeries(_ series: String, among candidates: [Meeting]) -> [Meeting] {
        candidates.filter { $0.calendarEvent?.seriesID == series }.sorted { $0.date < $1.date }
    }

    /// The project every one of `meetings` is in, if they share one and it's still open: the
    /// project a new meeting in their series starts in.
    public static func sharedProject(of meetings: [Meeting]) -> Project? {
        guard let project = meetings.first?.project, !project.isCompleted,
              meetings.allSatisfy({ $0.project?.id == project.id }) else { return nil }
        return project
    }

    /// Earlier meetings with the same people, newest first: instances of the same recurring event,
    /// and meetings whose attendees overlap this one's by at least half of everyone in either,
    /// leaving `me` out since I'm at all of them.
    public func previous(among candidates: [Meeting], me: UUID?, limit: Int = 5) -> [(meeting: Meeting, match: PreviousMatch)] {
        let series = calendarEvent?.seriesID
        let people = Set(attendees.map(\.id)).subtracting([me].compactMap { $0 })
        var found: [(meeting: Meeting, match: PreviousMatch)] = []
        for other in candidates where other.id != id && other.date < date {
            if let series, other.calendarEvent?.seriesID == series {
                found.append((other, .series))
                continue
            }
            let theirs = Set(other.attendees.map(\.id)).subtracting([me].compactMap { $0 })
            let union = people.union(theirs)
            guard !union.isEmpty else { continue }
            if people.intersection(theirs).count * 2 >= union.count {
                found.append((other, .attendees))
            }
        }
        return Array(found.sorted { $0.meeting.date > $1.meeting.date }.prefix(limit))
    }
}

/// What prep notes for a meeting draw on beyond its page: the last meeting with these people, the
/// projects their work is filed under, and what was closed in between.
public enum MeetingPrep {
    /// The meetings to read before this one, newest first: the latest `count` earlier instances of
    /// the series, topped up with the latest meetings with mostly the same people. `previous` is
    /// newest first, as `Meeting.previous` returns.
    public static func recent(
        of previous: [(meeting: Meeting, match: Meeting.PreviousMatch)], count: Int = 2
    ) -> [(meeting: Meeting, match: Meeting.PreviousMatch)] {
        let chosen = (previous.filter { $0.match == .series } + previous.filter { $0.match == .attendees }).prefix(count)
        return chosen.sorted { $0.meeting.date > $1.meeting.date }
    }

    /// Open projects linked to the meeting, most links first: its own project and earlier meetings',
    /// the projects of todos filed in any of them, and of todos tagging an attendee other than me
    /// that are open or were completed in the last `recentDays`.
    public static func relatedProjects(
        for meeting: Meeting, previous: [Meeting], todos: [Todo], me: UUID?,
        now: Date = .now, recentDays: Int = 60, limit: Int = 3
    ) -> [Project] {
        let meetings = Set(([meeting] + previous).map(\.id))
        let people = Set(meeting.attendees.map(\.id)).subtracting([me].compactMap { $0 })
        let recent = Calendar.current.date(byAdding: .day, value: -recentDays, to: now)!
        var links: [UUID: (project: Project, count: Int)] = [:]
        func link(_ project: Project?) {
            guard let project, !project.isCompleted else { return }
            links[project.id, default: (project, 0)].count += 1
        }
        ([meeting] + previous).forEach { link($0.project) }
        for todo in todos where !todo.isTrashed {
            if let filedIn = todo.meeting?.id, meetings.contains(filedIn) {
                link(todo.project)
            } else if (todo.completedDate.map { $0 >= recent } ?? true), todo.people.contains(where: { people.contains($0.id) }) {
                link(todo.project)
            }
        }
        return links.values
            .sorted { ($0.count, -$0.project.sortOrder) > ($1.count, -$1.project.sortOrder) }
            .prefix(limit)
            .map(\.project)
    }

    /// Todos completed after `since` and by the meeting's start, tagging an attendee other than me
    /// or in one of `projects`, most recent first.
    public static func completed(
        for meeting: Meeting, since: Date, projects: [Project], todos: [Todo], me: UUID?
    ) -> [Todo] {
        let people = Set(meeting.attendees.map(\.id)).subtracting([me].compactMap { $0 })
        let projectIDs = Set(projects.map(\.id))
        return todos
            .filter { todo in
                guard !todo.isTrashed, let done = todo.completedDate, done > since, done <= meeting.date else { return false }
                return todo.project.map { projectIDs.contains($0.id) } ?? false
                    || todo.people.contains { people.contains($0.id) }
            }
            .sorted { $0.completedDate! > $1.completedDate! }
    }
}
