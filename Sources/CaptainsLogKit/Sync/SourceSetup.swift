import Foundation
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "setup")

/// How far a sync source's setup has got, in the order the steps happen.
public enum SourceSetup: Int, Comparable, Sendable {
    case notInstalled
    case notLoggedIn
    /// Logged in, but without the scope the source needs (calendar access unticked on Google's consent screen).
    case missingScope
    /// Nothing to sync yet: no repos added on the Pull Requests tab.
    case notConfigured
    case ready

    public static func < (lhs: SourceSetup, rhs: SourceSetup) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum SyncSetupError: Error, LocalizedError {
    case notInstalled(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let tool): "\(tool) isn't installed"
        }
    }
}

/// The command-line tools sync shells out to, found on the PATH `runProcess` gives its children.
public enum SyncTool: String, Sendable {
    case gh

    public var path: String? { findExecutable(rawValue) }

    func requirePath() throws -> String {
        guard let path else { throw SyncSetupError.notInstalled(rawValue) }
        return path
    }
}

public enum SetupCheck {
    /// No network: `gh auth token` only reads the stored token, so being offline doesn't pass for logged out.
    /// An expired token passes, and shows up as a sync error instead.
    public static func github(repos: [String]) async -> SourceSetup {
        guard let gh = SyncTool.gh.path else { return .notInstalled }
        do {
            _ = try await runProcess(gh, arguments: ["auth", "token"], timeout: .seconds(15))
        } catch {
            return .notLoggedIn
        }
        return repos.isEmpty ? .notConfigured : .ready
    }

    /// No network, and no prompt: reads the scopes the stored login was granted, not the token. A login
    /// Google has since revoked passes, until a refresh finds out and deletes it. Nil when the Keychain
    /// can't be read, which says nothing about the login.
    public static func calendar() -> SourceSetup? {
        do {
            return calendarSetup(scopes: try GoogleKeychain.grantedScopes())
        } catch {
            logger.error("Couldn't read the calendar login: \(error)")
            return nil
        }
    }

    /// Nil scopes means logged out. A `calendar.readonly` login counts as missing its scope.
    public static func calendarSetup(scopes: [String]?) -> SourceSetup {
        guard let scopes else { return .notLoggedIn }
        return scopes.contains(GoogleLogin.scope) ? .ready : .missingScope
    }
}
