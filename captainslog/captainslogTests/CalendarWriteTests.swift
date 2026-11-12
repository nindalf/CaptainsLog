import Foundation
import Testing
import CaptainsLogKit

/// The decline patch replaces `attendees`, so it must carry only my own response and say the rest were omitted.
struct CalendarWriteTests {
    private func event(_ json: String) throws -> GoogleCalendarEvent {
        try JSONDecoder().decode(GoogleCalendarEvent.self, from: Data(json.utf8))
    }

    private func body(_ json: String) throws -> [String: Any] {
        let text = try CalendarWrite.declineBody(for: try event(json))
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test func declinesOnlyMyOwnResponse() throws {
        let patch = try body(#"""
            {"id": "e", "organizer": {"email": "them@x.com"},
             "attendees": [{"email": "them@x.com", "organizer": true, "responseStatus": "accepted"},
                           {"email": " me@x.com ", "self": true, "responseStatus": "needsAction"},
                           {"email": "other@x.com", "responseStatus": "accepted"}]}
            """#)
        #expect(patch["attendeesOmitted"] as? Bool == true)
        let attendees = try #require(patch["attendees"] as? [[String: String]])
        #expect(attendees == [["email": "me@x.com", "responseStatus": "declined"]])
    }

    @Test func refusesToDeclineMyOwnEvent() throws {
        #expect(throws: CalendarWriteError.self) {
            try body(#"""
                {"id": "e", "organizer": {"email": "me@x.com", "self": true},
                 "attendees": [{"email": "me@x.com", "self": true, "organizer": true, "responseStatus": "accepted"},
                               {"email": "them@x.com", "responseStatus": "accepted"}]}
                """#)
        }
    }

    @Test func refusesWhenImNotAGuest() throws {
        #expect(throws: CalendarWriteError.self) {
            try body(#"{"id": "e", "organizer": {"email": "them@x.com"}, "attendees": [{"email": "them@x.com"}]}"#)
        }
    }
}
