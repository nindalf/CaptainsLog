import Foundation
import Testing
import CaptainsLogKit

struct SourceSetupTests {
    private func setup(_ json: String) -> SourceSetup {
        SetupCheck.calendarSetup(authStatus: Data(json.utf8))
    }

    @Test func loggedOut() {
        #expect(setup(#"{"auth_method": "none", "credential_source": "none", "token_cache_exists": false}"#) == .notLoggedIn)
    }

    /// An older login that can read the calendar but not decline or delete events.
    @Test func loggedInToReadOnlyNeedsToLogInAgain() {
        #expect(setup(#"{"auth_method": "oauth2", "scopes": ["openid", "https://www.googleapis.com/auth/calendar.readonly"]}"#) == .missingScope)
        #expect(setup(#"{"auth_method": "oauth2", "scopes": ["https://www.googleapis.com/auth/calendar.events"]}"#) == .missingScope)
    }

    @Test func loggedInWithFullCalendar() {
        #expect(setup(#"{"auth_method": "oauth2", "scopes": ["https://www.googleapis.com/auth/calendar", "email"]}"#) == .ready)
    }

    /// Logged in to gws for Gmail or Drive, never for the calendar.
    @Test func loggedInWithoutCalendar() {
        #expect(setup(#"{"auth_method": "oauth2", "scopes": ["https://www.googleapis.com/auth/gmail.modify", "https://www.googleapis.com/auth/calendarx"]}"#) == .missingScope)
    }

    @Test func noScopesListedLeavesItToSync() {
        #expect(setup(#"{"auth_method": "oauth2"}"#) == .ready)
    }

    @Test func unreadable() {
        #expect(setup("Using keyring backend: keyring") == .notLoggedIn)
    }
}
