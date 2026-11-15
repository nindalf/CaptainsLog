import Foundation
import Testing
import CaptainsLogKit

/// From the scopes Google granted the stored login.
struct SourceSetupTests {
    @Test func noLoginIsLoggedOut() {
        #expect(SetupCheck.calendarSetup(scopes: nil) == .notLoggedIn)
    }

    /// Google's consent screen lets the user untick calendar access, or a login may only read.
    @Test func withoutFullCalendarNeedsToLogInAgain() {
        #expect(SetupCheck.calendarSetup(scopes: []) == .missingScope)
        #expect(SetupCheck.calendarSetup(scopes: ["https://www.googleapis.com/auth/calendar.readonly"]) == .missingScope)
        #expect(SetupCheck.calendarSetup(scopes: ["https://www.googleapis.com/auth/calendar.events"]) == .missingScope)
        #expect(SetupCheck.calendarSetup(scopes: ["https://www.googleapis.com/auth/calendarx"]) == .missingScope)
    }

    @Test func fullCalendarIsReady() {
        #expect(SetupCheck.calendarSetup(scopes: ["openid", "https://www.googleapis.com/auth/calendar"]) == .ready)
    }
}
