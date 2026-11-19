import Foundation
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "sync.calendar")

public enum CalendarWriteError: Error, LocalizedError {
    case organisedByMe
    case notInvited
    case notOrganiser

    public var errorDescription: String? {
        switch self {
        case .organisedByMe: "You organised this event, so there's nothing to decline. Delete it instead."
        case .notInvited: "You're not a guest of this event, so there's nothing to decline."
        case .notOrganiser: "Only the organiser can delete this event. Decline it instead."
        }
    }
}

/// The app's only writes to Google Calendar, on timed events, which all come from the primary calendar.
/// Each reads the event first: `isOrganizedByMe` is false for events last synced before schema V3. Guests are told.
public enum CalendarWrite {
    public static func decline(eventID: String) async throws {
        let body = try declineBody(for: try await api.event(id: eventID))
        try await api.patchEvent(id: eventID, body: body)
        logger.info("Declined a calendar event")
    }

    public static func delete(eventID: String) async throws {
        guard try await api.event(id: eventID).organizer?.isSelf == true else { throw CalendarWriteError.notOrganiser }
        try await api.deleteEvent(id: eventID)
        logger.info("Deleted a calendar event")
    }

    /// Only my own response: a patch's `attendees` replaces the whole list, and `attendeesOmitted`
    /// tells Google the rest were left out on purpose, so no other guest is touched.
    public static func declineBody(for event: GoogleCalendarEvent) throws -> Data {
        guard event.organizer?.isSelf != true else { throw CalendarWriteError.organisedByMe }
        guard let me = event.attendees?.first(where: { $0.isSelf == true }) else { throw CalendarWriteError.notInvited }
        let body: [String: Any] = [
            "attendeesOmitted": true,
            "attendees": [["email": me.email, "responseStatus": "declined"]],
        ]
        return try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
    }

    private static var api: GoogleCalendarAPI { .shared }
}
