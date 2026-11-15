import Foundation
import Synchronization
import Testing
import CaptainsLogKit

/// Token refresh and the Calendar requests, against a stand-in for Google.
struct GoogleAuthTests {
    private static let login = GoogleCredentials(clientID: "id", clientSecret: "secret", refreshToken: "refresh")

    /// Answers the token endpoint and the Calendar API, and records what it was asked.
    private final class Google: Sendable {
        private struct State {
            var refreshes = 0
            var deleted: [GoogleCredentials] = []
            var requests: [URLRequest] = []
            var unauthorized: Int
        }

        private let state: Mutex<State>
        private let refreshError: String?
        private let refreshDelay: Duration

        /// `unauthorized`: Calendar requests answered 401 before the rest succeed.
        init(refreshError: String? = nil, unauthorized: Int = 0, refreshDelay: Duration = .zero) {
            state = Mutex(State(unauthorized: unauthorized))
            self.refreshError = refreshError
            self.refreshDelay = refreshDelay
        }

        var refreshes: Int { state.withLock { $0.refreshes } }
        var deleted: [GoogleCredentials] { state.withLock { $0.deleted } }
        var requests: [URLRequest] { state.withLock { $0.requests } }

        var store: GoogleCredentialStore {
            GoogleCredentialStore(load: { GoogleAuthTests.login }, delete: { credentials in
                self.state.withLock { $0.deleted.append(credentials) }
            })
        }

        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            let url = request.url!
            if url.host == "oauth2.googleapis.com" {
                let form = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
                #expect(form.contains("grant_type=refresh_token") && form.contains("refresh_token=refresh"))
                try await Task.sleep(for: refreshDelay)
                if let refreshError {
                    return (Data(#"{"error":"\#(refreshError)"}"#.utf8), response(url, 400))
                }
                let n = state.withLock { $0.refreshes += 1; return $0.refreshes }
                return (Data(#"{"access_token":"access-\#(n)","expires_in":3600}"#.utf8), response(url, 200))
            }
            let status = state.withLock {
                $0.requests.append(request)
                guard $0.unauthorized > 0 else { return 200 }
                $0.unauthorized -= 1
                return 401
            }
            return (Data(#"{"id":"e","items":[{"id":"primary","primary":true}]}"#.utf8), response(url, status))
        }

        private func response(_ url: URL, _ status: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        }
    }

    private final class Clock: Sendable {
        private let time = Mutex(Date(timeIntervalSince1970: 1_000_000))
        var now: Date { time.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { time.withLock { $0 += seconds } }
    }

    private func auth(_ google: Google, _ clock: Clock = Clock()) -> GoogleAuth {
        GoogleAuth(store: google.store, send: google.send, now: { clock.now })
    }

    @Test func refreshesOnlyNearExpiry() async throws {
        let google = Google()
        let clock = Clock()
        let auth = auth(google, clock)
        #expect(try await auth.accessToken() == "access-1")
        clock.advance(3000)
        #expect(try await auth.accessToken() == "access-1")
        // Within a minute of the hour's expiry.
        clock.advance(570)
        #expect(try await auth.accessToken() == "access-2")
        #expect(google.refreshes == 2)
    }

    /// The second caller arrives while the first's refresh is still waiting on Google.
    @Test func concurrentCallersShareOneRefresh() async throws {
        let google = Google(refreshDelay: .milliseconds(200))
        let auth = auth(google)
        async let a = auth.accessToken()
        async let b = auth.accessToken()
        #expect(try await [a, b] == ["access-1", "access-1"])
        #expect(google.refreshes == 1)
    }

    /// Google revoked the login: it's deleted, so setup asks to log in again.
    @Test func invalidGrantLogsOut() async {
        let google = Google(refreshError: "invalid_grant")
        await #expect {
            try await auth(google).accessToken()
        } throws: { error in
            if case GoogleAuthError.loggedOut = error { true } else { false }
        }
        #expect(google.deleted == [Self.login])
    }

    /// Any other refresh failure says nothing about the login.
    @Test func otherRefreshFailuresKeepTheLogin() async {
        let google = Google(refreshError: "internal_failure")
        await #expect {
            try await auth(google).accessToken()
        } throws: { error in
            if case GoogleAuthError.tokenRequest(error: "internal_failure", _) = error { true } else { false }
        }
        #expect(google.deleted.isEmpty)
    }

    @Test func retriesOnceAfterA401WithAFreshToken() async throws {
        let google = Google(unauthorized: 1)
        let api = GoogleCalendarAPI(auth: auth(google), send: google.send)
        #expect(try await api.calendars().map(\.id) == ["primary"])
        #expect(google.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer access-1", "Bearer access-2"])
    }

    @Test func givesUpAfterASecond401() async {
        let google = Google(unauthorized: 2)
        let api = GoogleCalendarAPI(auth: auth(google), send: google.send)
        await #expect(throws: GoogleAPIError.self) { try await api.calendars() }
        #expect(google.requests.count == 2)
    }

    /// Calendar ids hold `#` and `@`, which have to be escaped in the path.
    @Test func escapesTheCalendarID() async throws {
        let google = Google()
        let api = GoogleCalendarAPI(auth: auth(google), send: google.send)
        _ = try await api.events(calendarID: "en.uk#holiday@group.v.calendar.google.com", in: DateInterval(start: .now, duration: 60))
        let url = try #require(google.requests.first?.url)
        #expect(url.path(percentEncoded: true) == "/calendar/v3/calendars/en.uk%23holiday%40group.v.calendar.google.com/events")
    }

    /// Both writes tell guests, and go to the primary calendar, the only one timed events come from.
    @Test func writesTellGuests() async throws {
        let google = Google()
        let api = GoogleCalendarAPI(auth: auth(google), send: google.send)
        let body = Data(#"{"attendeesOmitted":true}"#.utf8)
        try await api.patchEvent(id: "e1", body: body)
        try await api.deleteEvent(id: "e1")
        let (patch, delete) = (google.requests[0], google.requests[1])
        #expect(patch.httpMethod == "PATCH")
        #expect(patch.httpBody == body)
        #expect(patch.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(delete.httpMethod == "DELETE")
        for request in [patch, delete] {
            #expect(request.url?.absoluteString == "https://www.googleapis.com/calendar/v3/calendars/primary/events/e1?sendUpdates=all")
        }
    }

    /// RFC 7636's example.
    @Test func pkceChallenge() {
        #expect(GoogleLogin.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
}
