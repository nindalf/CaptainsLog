import Foundation
import Testing
import CaptainsLogKit

struct GoogleCalendarAPITests {
    private struct Item: Decodable, Equatable {
        let id: String
    }

    private func pages(_ lines: String...) -> Data {
        Data(lines.joined(separator: "\n").utf8)
    }

    @Test func joinsEveryPage() throws {
        let data = pages(
            #"{"items":[{"id":"a"},{"id":"b"}],"nextPageToken":"t1"}"#,
            #"{"nextPageToken":"t2"}"#,
            #"{"items":[{"id":"c"}]}"#
        )
        let items: [Item] = try decodeGoogleCalendarPages(data)
        #expect(items.map(\.id) == ["a", "b", "c"])
    }

    /// gws stops at its page limit with a token left over; a partial list would read as deletions.
    @Test func throwsWhenTheLastPageHasMoreToCome() {
        let data = pages(#"{"items":[{"id":"a"}],"nextPageToken":"t1"}"#)
        #expect(throws: CalendarSyncError.self) {
            let _: [Item] = try decodeGoogleCalendarPages(data)
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
