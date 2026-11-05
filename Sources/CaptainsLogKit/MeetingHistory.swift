import Foundation

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
