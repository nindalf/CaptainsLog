import Foundation
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "setup")

/// How far a sync source's setup has got, in the order the steps happen.
public enum SourceSetup: Int, Comparable, Sendable {
    case notInstalled
    case notLoggedIn
    /// Logged in, but without the scope the source needs (gws logged in for other APIs, or only to read the calendar).
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
    case gh, gws

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

    /// Nil when the check itself fails (gws errors, times out, or prints something unreadable), which
    /// says nothing about the login: only a status gws reports counts as logged out.
    public static func calendar() async -> SourceSetup? {
        guard let gws = SyncTool.gws.path else { return .notInstalled }
        do {
            let result = try await runProcess(gws, arguments: ["auth", "status"], timeout: .seconds(15))
            return calendarSetup(authStatus: result.stdout)
        } catch {
            logger.error("gws auth status failed: \(error)")
            return nil
        }
    }

    /// From `gws auth status`, which exits 0 logged in or not. Nil when unreadable.
    public static func calendarSetup(authStatus: Data) -> SourceSetup? {
        struct Status: Decodable {
            let auth_method: String?
            let scopes: [String]?
        }
        guard let status = try? JSONDecoder().decode(Status.self, from: authStatus) else {
            logger.error("Unreadable gws auth status")
            return nil
        }
        guard let method = status.auth_method, method != "none" else { return .notLoggedIn }
        // Older gws doesn't list scopes; let sync find out.
        guard let scopes = status.scopes else { return .ready }
        // The full scope: the app declines and deletes events as well as reading them.
        return scopes.contains("https://www.googleapis.com/auth/calendar") ? .ready : .missingScope
    }
}
