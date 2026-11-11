import Foundation

/// The OAuth client gws logs in through. Builds carry it as `GoogleClient.json`, which is gitignored:
/// Google doesn't treat a Desktop client's secret as confidential, but it stays out of the public repo.
public struct GoogleClient: Decodable, Sendable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    /// Nil in a build without the file, which falls back to a login command to paste.
    public static func bundled(in bundle: Bundle = .main) -> GoogleClient? {
        guard let url = bundle.url(forResource: "GoogleClient", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let client = try? JSONDecoder().decode(GoogleClient.self, from: data),
            !client.clientID.isEmpty, !client.clientSecret.isEmpty
        else { return nil }
        return client
    }
}

/// Where an in-app calendar login has got.
public enum CalendarLoginState: Equatable, Sendable {
    case idle
    /// gws is starting and hasn't printed its link yet.
    case starting
    /// gws is waiting for Google to redirect back to it, once the user finishes at `url`.
    case waiting(URL)
    case failed(String)
}

public enum GoogleLogin {
    /// `gws auth login` for Calendar only, which asks for the full `calendar` scope. With no terminal it
    /// shows no scope picker: it prints the consent link on stderr, listens on localhost for Google's
    /// redirect, saves the token and exits. It replaces any other gws login.
    public static func run(
        client: GoogleClient, timeout: Duration, onURL: @escaping @Sendable (URL) -> Void
    ) async throws {
        try await runWatchingStderr(
            try SyncTool.gws.requirePath(),
            arguments: ["auth", "login", "--services", "calendar"],
            environment: [
                "GOOGLE_WORKSPACE_CLI_CLIENT_ID": client.clientID,
                "GOOGLE_WORKSPACE_CLI_CLIENT_SECRET": client.clientSecret,
            ],
            timeout: timeout
        ) { line in
            if let url = authURL(in: line) { onURL(url) }
        }
    }

    /// gws's error, without the link it printed first.
    public static func failureReason(_ stderr: String) -> String {
        let lines = stderr.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && authURL(in: $0) == nil && !$0.hasPrefix("Open this URL") }
        return lines.isEmpty ? "gws auth login failed" : lines.joined(separator: "\n")
    }

    /// The consent link, on a line of its own in gws's output.
    public static func authURL(in line: String) -> URL? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("https://accounts.google.com/") else { return nil }
        return URL(string: text)
    }
}
