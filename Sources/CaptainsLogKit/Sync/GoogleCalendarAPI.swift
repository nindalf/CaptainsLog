import Foundation

// The five Google Calendar API calls the app makes, and Google's JSON for them.

public enum GoogleAPIError: Error, LocalizedError {
    /// `reason` is such as `accessNotConfigured`, when the API isn't enabled in the OAuth client's project.
    case http(status: Int, message: String?, reason: String?)
    case repeatedPage

    init(status: Int, body: Data) {
        struct Envelope: Decodable {
            struct Detail: Decodable {
                let message: String?
                let errors: [Reason]?
            }
            struct Reason: Decodable { let reason: String? }
            let error: Detail
        }
        let detail = (try? JSONDecoder().decode(Envelope.self, from: body))?.error
        self = .http(status: status, message: detail?.message, reason: detail?.errors?.first?.reason)
    }

    public var errorDescription: String? {
        switch self {
        case .http(let status, let message, let reason):
            "Google Calendar returned \(status): \(message ?? "no message")\(reason.map { " (\($0))" } ?? "")"
        case .repeatedPage:
            "Google Calendar sent the same page twice"
        }
    }
}

private struct GoogleCalendarPage<Item: Decodable>: Decodable {
    let items: [Item]?
    let nextPageToken: String?
}

public struct GoogleCalendarAPI: Sendable {
    public static let shared = GoogleCalendarAPI(auth: .shared, send: urlSessionSend)

    private let auth: GoogleAuth
    private let send: HTTPSend

    public init(auth: GoogleAuth, send: @escaping HTTPSend) {
        self.auth = auth
        self.send = send
    }

    public func calendars() async throws -> [GoogleCalendarListEntry] {
        try await Self.allPages { token in
            try await request("GET", ["users", "me", "calendarList"], query: Self.pageQuery(token))
        }
    }

    /// Instances of recurring events, not the series, within `range`.
    public func events(calendarID: String, in range: DateInterval) async throws -> [GoogleCalendarEvent] {
        let query = [
            URLQueryItem(name: "timeMin", value: iso8601String(range.start)),
            URLQueryItem(name: "timeMax", value: iso8601String(range.end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "maxResults", value: "2500"),
        ]
        return try await Self.allPages { token in
            try await request("GET", ["calendars", calendarID, "events"], query: query + Self.pageQuery(token))
        }
    }

    public func event(id: String) async throws -> GoogleCalendarEvent {
        try JSONDecoder().decode(GoogleCalendarEvent.self, from: try await request("GET", Self.primaryEvent(id)))
    }

    /// Guests are told.
    public func patchEvent(id: String, body: Data) async throws {
        _ = try await request("PATCH", Self.primaryEvent(id), query: [URLQueryItem(name: "sendUpdates", value: "all")], body: body)
    }

    /// Guests are told.
    public func deleteEvent(id: String) async throws {
        _ = try await request("DELETE", Self.primaryEvent(id), query: [URLQueryItem(name: "sendUpdates", value: "all")])
    }

    /// Every page, to the last: a partial list would read as deletions.
    public static func allPages<Item: Decodable>(_ fetch: (String?) async throws -> Data) async throws -> [Item] {
        var items: [Item] = []
        var token: String?
        repeat {
            let page = try JSONDecoder().decode(GoogleCalendarPage<Item>.self, from: try await fetch(token))
            items += page.items ?? []
            if let next = page.nextPageToken, next == token { throw GoogleAPIError.repeatedPage }
            token = page.nextPageToken
        } while token != nil
        return items
    }

    private static func pageQuery(_ token: String?) -> [URLQueryItem] {
        token.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? []
    }

    /// Timed events, the only ones the app writes to, all come from the primary calendar.
    private static func primaryEvent(_ id: String) -> [String] { ["calendars", "primary", "events", id] }

    /// Retries once on a 401, with a refreshed token.
    private func request(_ method: String, _ path: [String], query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        var retried = false
        while true {
            let token = try await auth.accessToken()
            var request = URLRequest(url: Self.url(path, query: query), timeoutInterval: 60)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (data, response) = try await send(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401, !retried {
                await auth.reject(token)
                retried = true
                continue
            }
            guard (200..<300).contains(status) else { throw GoogleAPIError(status: status, body: data) }
            return data
        }
    }

    /// Each segment percent-encoded: calendar ids hold `#` and `@`.
    static func url(_ path: [String], query: [URLQueryItem]) -> URL {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3")!
        components.percentEncodedPath += path.map {
            "/" + $0.addingPercentEncoding(withAllowedCharacters: GoogleOAuth.unreserved)!
        }.joined()
        if !query.isEmpty {
            components.queryItems = query
            // URLComponents leaves `+` alone, which Google reads as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        return components.url!
    }
}

func iso8601String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
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
    public let organizer: GoogleCalendarOrganizer?
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

public struct GoogleCalendarOrganizer: Decodable, Sendable {
    public let email: String?
    public let isSelf: Bool?

    enum CodingKeys: String, CodingKey {
        case email
        case isSelf = "self"
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
