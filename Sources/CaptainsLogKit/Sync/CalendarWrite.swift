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
    /// Never from a sandbox: it doesn't sync, so its events aren't real ones.
    public static var isAvailable: Bool { !Store.isScratch }

    public static func decline(eventID: String) async throws {
        let body = try declineBody(for: try await fetch(eventID))
        _ = try await gws(["calendar", "events", "patch", "--params", try params(eventID), "--json", body])
        logger.info("Declined a calendar event")
    }

    public static func delete(eventID: String) async throws {
        guard try await fetch(eventID).organizer?.isSelf == true else { throw CalendarWriteError.notOrganiser }
        _ = try await gws(["calendar", "events", "delete", "--params", try params(eventID)])
        logger.info("Deleted a calendar event")
    }

    /// Only my own response: a patch's `attendees` replaces the whole list, and `attendeesOmitted`
    /// tells Google the rest were left out on purpose, so no other guest is touched.
    public static func declineBody(for event: GoogleCalendarEvent) throws -> String {
        guard event.organizer?.isSelf != true else { throw CalendarWriteError.organisedByMe }
        guard let me = event.attendees?.first(where: { $0.isSelf == true }) else { throw CalendarWriteError.notInvited }
        let body: [String: Any] = [
            "attendeesOmitted": true,
            "attendees": [["email": me.email, "responseStatus": "declined"]],
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: body, options: .sortedKeys), as: UTF8.self)
    }

    private static func fetch(_ eventID: String) async throws -> GoogleCalendarEvent {
        let params = try JSONSerialization.data(withJSONObject: ["calendarId": "primary", "eventId": eventID])
        let result = try await gws(["calendar", "events", "get", "--params", String(decoding: params, as: UTF8.self)])
        return try JSONDecoder().decode(GoogleCalendarEvent.self, from: result.stdout)
    }

    private static func params(_ eventID: String) throws -> String {
        let params: [String: Any] = ["calendarId": "primary", "eventId": eventID, "sendUpdates": "all"]
        return String(decoding: try JSONSerialization.data(withJSONObject: params, options: .sortedKeys), as: UTF8.self)
    }

    /// From the temporary folder: gws saves a delete's empty response as `download.html` where it runs.
    private static func gws(_ arguments: [String]) async throws -> ProcessResult {
        try await runProcess(
            try SyncTool.gws.requirePath(), arguments: arguments,
            workingDirectory: FileManager.default.temporaryDirectory, timeout: .seconds(30))
    }
}
