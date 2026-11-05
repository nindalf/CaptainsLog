import Foundation

// Google Calendar API responses as `gws calendar ... list --page-all` prints them.

public enum CalendarSyncError: Error, LocalizedError {
    case truncated

    public var errorDescription: String? {
        switch self {
        case .truncated:
            return "gws stopped before the last page of calendar events"
        }
    }
}

private struct GoogleCalendarPage<Item: Decodable>: Decodable {
    let items: [Item]?
    let nextPageToken: String?
}

/// The items of every page `gws --page-all` printed, one JSON page per line. Throws if the last page
/// still has a `nextPageToken`: gws stopped at its page limit, and a partial list would read as deletions.
public func decodeGoogleCalendarPages<Item: Decodable>(_ data: Data) throws -> [Item] {
    let decoder = JSONDecoder()
    var items: [Item] = []
    var nextPageToken: String?
    for line in data.split(separator: UInt8(ascii: "\n")) {
        let page = try decoder.decode(GoogleCalendarPage<Item>.self, from: Data(line))
        items += page.items ?? []
        nextPageToken = page.nextPageToken
    }
    guard nextPageToken == nil else { throw CalendarSyncError.truncated }
    return items
}

public struct GoogleCalendarListEntry: Decodable, Sendable {
    public let id: String
    public let summary: String?
    public let primary: Bool?
}

public struct GoogleCalendarEvent: Decodable, Sendable {
    public let id: String
    public let summary: String?
    public let start: GoogleCalendarTime?
    public let end: GoogleCalendarTime?
    public let location: String?
    public let attendees: [GoogleCalendarAttendee]?
    public let eventType: String?
    public let status: String?
    public let hangoutLink: String?
    /// Set on each instance of a recurring event.
    public let recurringEventId: String?

    public var isAllDay: Bool { start?.date != nil }

    public var isDeclinedByMe: Bool {
        attendees?.contains { $0.isSelf == true && $0.responseStatus == "declined" } == true
    }
}

public struct GoogleCalendarTime: Decodable, Sendable {
    public let date: String?
    public let dateTime: String?
}

public struct GoogleCalendarAttendee: Decodable, Sendable {
    public let email: String
    public let displayName: String?
    public let responseStatus: String?
    public let isSelf: Bool?
    public let resource: Bool?

    enum CodingKeys: String, CodingKey {
        case email, displayName, responseStatus
        case isSelf = "self"
        case resource
    }

    // Trimmed here so the email lookup matches the trimmed value `Person` stores.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decode(String.self, forKey: .email).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = try container.decodeIfPresent(String.self, forKey: .displayName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = name?.isEmpty == false ? name : nil
        responseStatus = try container.decodeIfPresent(String.self, forKey: .responseStatus)
        isSelf = try container.decodeIfPresent(Bool.self, forKey: .isSelf)
        resource = try container.decodeIfPresent(Bool.self, forKey: .resource)
    }

    var emailDomain: String? {
        email.split(separator: "@").last.map { $0.lowercased() }
    }
}
