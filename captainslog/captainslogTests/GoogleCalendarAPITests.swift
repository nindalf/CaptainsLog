import Foundation
import Testing
import CaptainsLogKit

struct GoogleCalendarAPITests {
    private struct Item: Decodable, Equatable {
        let id: String
    }

    /// Follows `nextPageToken` until a page has none, asking for each page by the last one's token.
    @Test func joinsEveryPage() async throws {
        let pages = [
            nil: #"{"items":[{"id":"a"},{"id":"b"}],"nextPageToken":"t1"}"#,
            "t1": #"{"nextPageToken":"t2"}"#,
            "t2": #"{"items":[{"id":"c"}]}"#,
        ]
        var asked: [String?] = []
        let items: [Item] = try await GoogleCalendarAPI.allPages { token in
            asked.append(token)
            return Data(try #require(pages[token]).utf8)
        }
        #expect(items.map(\.id) == ["a", "b", "c"])
        #expect(asked == [nil, "t1", "t2"])
    }

    @Test func stopsWhenGoogleRepeatsAPage() async {
        await #expect(throws: GoogleAPIError.self) {
            let _: [Item] = try await GoogleCalendarAPI.allPages { _ in Data(#"{"items":[],"nextPageToken":"t1"}"#.utf8) }
        }
    }

    private func event(attendees: String) throws -> GoogleCalendarEvent {
        let json = #"{"id":"e","start":{"dateTime":"2026-11-02T14:00:00Z"},"attendees":"# + attendees + "}"
        return try JSONDecoder().decode(GoogleCalendarEvent.self, from: Data(json.utf8))
    }

    @Test func declinedOnlyWhenIDeclined() throws {
        let mine = try event(attendees: #"[{"email":"me@x.com","self":true,"responseStatus":"declined"}]"#)
        let theirs = try event(attendees: #"""
            [{"email":"me@x.com","self":true,"responseStatus":"accepted"},
             {"email":"you@x.com","responseStatus":"declined"}]
            """#)
        let noAttendees = try event(attendees: "[]")
        #expect(mine.isDeclinedByMe)
        #expect(!theirs.isDeclinedByMe)
        #expect(!noAttendees.isDeclinedByMe)
    }
}
