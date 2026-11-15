import Foundation
import Security
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "sync.calendar")

public enum GoogleAuthError: Error, LocalizedError {
    case loggedOut
    case keychain(OSStatus)
    case tokenRequest(error: String, description: String?)

    public var errorDescription: String? {
        switch self {
        case .loggedOut:
            "Not logged in to Google Calendar. Log in on the Calendar tab."
        case .keychain(let status):
            "Couldn't use the Google login in the Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)")"
        case .tokenRequest(let error, let description):
            "Google's token request failed: \([error, description].compactMap { $0 }.joined(separator: ", "))"
        }
    }
}

public typealias HTTPSend = @Sendable (URLRequest) async throws -> (Data, URLResponse)

let urlSessionSend: HTTPSend = { try await URLSession.shared.data(for: $0) }

/// Where `GoogleAuth` finds the login, and forgets it once Google has revoked it.
public struct GoogleCredentialStore: Sendable {
    public var load: @Sendable () throws -> GoogleCredentials?
    /// Deletes the login only if it's still `credentials`: the app may have logged in again since.
    public var delete: @Sendable (_ credentials: GoogleCredentials) throws -> Void

    public init(
        load: @escaping @Sendable () throws -> GoogleCredentials?,
        delete: @escaping @Sendable (_ credentials: GoogleCredentials) throws -> Void
    ) {
        self.load = load
        self.delete = delete
    }

    static let keychain = GoogleCredentialStore(load: GoogleKeychain.load) { credentials in
        if try GoogleKeychain.load() == credentials { try GoogleKeychain.delete() }
    }
}

/// Hands out access tokens. Only the refresh token is stored; access tokens live in memory, one per
/// process, and are refreshed a minute before they expire, or after Google rejects one.
public actor GoogleAuth {
    public static let shared = GoogleAuth(store: .keychain, send: urlSessionSend)

    private let store: GoogleCredentialStore
    private let send: HTTPSend
    private let now: @Sendable () -> Date
    private var credentials: GoogleCredentials?
    private var access: (token: String, expiry: Date)?
    private var refreshing: Task<String, Error>?

    public init(store: GoogleCredentialStore, send: @escaping HTTPSend, now: @escaping @Sendable () -> Date = { .now }) {
        self.store = store
        self.send = send
        self.now = now
    }

    public func accessToken() async throws -> String {
        if let access, access.expiry.timeIntervalSince(now()) > 60 { return access.token }
        // Concurrent callers share one refresh.
        if let refreshing { return try await refreshing.value }
        let task = Task { try await refresh() }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    /// Google answered 401 to `token`: it was revoked or expired early, so the next call refreshes.
    public func reject(_ token: String) {
        if access?.token == token { access = nil }
    }

    func loggedIn(_ credentials: GoogleCredentials, accessToken: String, expiresIn: Int) {
        self.credentials = credentials
        access = (accessToken, now().addingTimeInterval(TimeInterval(expiresIn)))
    }

    /// `invalid_grant` means the login is gone (revoked, expired or replaced), so it's deleted and setup
    /// asks to log in again. Any other failure, the network's included, says nothing about the login.
    private func refresh() async throws -> String {
        guard let credentials = try credentials ?? store.load() else { throw GoogleAuthError.loggedOut }
        self.credentials = credentials
        do {
            let response = try await GoogleOAuth.requestToken(
                [
                    "grant_type": "refresh_token",
                    "refresh_token": credentials.refreshToken,
                    "client_id": credentials.clientID,
                    "client_secret": credentials.clientSecret,
                ], send: send)
            access = (response.accessToken, now().addingTimeInterval(TimeInterval(response.expiresIn)))
            return response.accessToken
        } catch GoogleAuthError.tokenRequest(error: "invalid_grant", _) {
            logger.error("Google revoked the calendar login")
            // A login during the refresh replaced these credentials; keep it.
            guard self.credentials == credentials else { throw GoogleAuthError.loggedOut }
            self.credentials = nil
            access = nil
            try store.delete(credentials)
            throw GoogleAuthError.loggedOut
        }
    }
}

struct GoogleTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    /// Only from exchanging a login's code.
    let refreshToken: String?
    /// Space-separated. Google's consent screen lets the user untick a scope.
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

enum GoogleOAuth {
    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    static func requestToken(_ form: [String: String], send: HTTPSend) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: tokenURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded(form).utf8)
        let (data, response) = try await send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            struct Failure: Decodable {
                let error: String
                let error_description: String?
            }
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            throw GoogleAuthError.tokenRequest(error: failure?.error ?? "HTTP \(status)", description: failure?.error_description)
        }
        return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
    }

    static func formEncoded(_ form: [String: String]) -> String {
        form.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: unreserved)!)" }
            .joined(separator: "&")
    }

    /// RFC 3986's unreserved characters, the only ones a form value or a path segment can carry as is.
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
