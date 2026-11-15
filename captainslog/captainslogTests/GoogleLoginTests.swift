import Foundation
import Testing
import CaptainsLogKit

/// The loopback half of the login, up to the point it would ask Google for a token, which isn't covered.
struct GoogleLoginTests {
    private let client = GoogleClient(clientID: "id.apps.googleusercontent.com", clientSecret: "secret")

    /// Starts a login and returns Google's consent link, with the task to await.
    private func start(timeout: Duration = .seconds(30)) async throws -> (URL, Task<Void, Error>) {
        let (links, continuation) = AsyncStream.makeStream(of: URL.self)
        let login = Task { [client] in
            try await GoogleLogin.run(client: client, timeout: timeout) { continuation.yield($0) }
        }
        var iterator = links.makeAsyncIterator()
        return (try #require(await iterator.next()), login)
    }

    private func redirect(_ link: URL, _ query: String) async throws -> (Int, String) {
        let items = URLComponents(url: link, resolvingAgainstBaseURL: false)!.queryItems!
        let base = items.first { $0.name == "redirect_uri" }!.value!
        let (data, response) = try await URLSession.shared.data(from: URL(string: base + "/" + query)!)
        return ((response as! HTTPURLResponse).statusCode, String(decoding: data, as: UTF8.self))
    }

    private func state(_ link: URL) -> String {
        URLComponents(url: link, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
    }

    @Test func asksForOfflineAccessToTheFullCalendarWithPKCE() async throws {
        let (link, login) = try await start()
        defer { login.cancel() }
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: link, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(items["scope"] == "https://www.googleapis.com/auth/calendar")
        #expect(items["access_type"] == "offline")
        #expect(items["prompt"] == "consent")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["redirect_uri"]?.hasPrefix("http://127.0.0.1:") == true)
    }

    /// Another login's redirect, or a stray request, is answered and ignored; Cancel in the browser ends it.
    @Test func ignoresOtherRequestsAndReportsACancel() async throws {
        let (link, login) = try await start()
        #expect(try await redirect(link, "favicon.ico").0 == 404)
        #expect(try await redirect(link, "?code=c&state=other").0 == 400)
        #expect(try await redirect(link, "?error=access_denied&state=\(state(link))").0 == 200)
        await #expect {
            try await login.value
        } throws: { error in
            if case GoogleLoginError.denied("access_denied") = error { true } else { false }
        }
    }

    @Test func timesOutAndClosesThePort() async throws {
        let (link, login) = try await start(timeout: .milliseconds(200))
        await #expect {
            try await login.value
        } throws: { error in
            if case GoogleLoginError.timedOut = error { true } else { false }
        }
        await #expect(throws: (any Error).self) { try await redirect(link, "?code=c&state=\(state(link))") }
    }

    @Test func cancellingClosesThePort() async throws {
        let (link, login) = try await start()
        login.cancel()
        await #expect(throws: CancellationError.self) { try await login.value }
        await #expect(throws: (any Error).self) { try await redirect(link, "?code=c&state=\(state(link))") }
    }
}
