import CryptoKit
import Foundation
import Network

/// The OAuth client the app logs in through. Builds carry it as `GoogleClient.json`, which is gitignored:
/// Google doesn't treat a Desktop client's secret as confidential, but it stays out of the public repo.
public struct GoogleClient: Decodable, Sendable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    /// Nil in a build without the file, which can't log in.
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
    /// Opening the local port Google redirects to.
    case starting
    /// Waiting for Google to redirect back, once the user finishes at `url`.
    case waiting(URL)
    case failed(String)
}

public enum GoogleLoginError: Error, LocalizedError {
    case timedOut
    case denied(String)
    case noRefreshToken

    public var errorDescription: String? {
        switch self {
        case .timedOut: "The login timed out. Try again."
        case .denied("access_denied"): "The login was cancelled in the browser."
        case .denied(let error): "Google refused the login: \(error)"
        case .noRefreshToken: "Google didn't send a refresh token. Try again."
        }
    }
}

public enum GoogleLogin {
    /// The full scope: the app declines and deletes events as well as reading them.
    public static let scope = "https://www.googleapis.com/auth/calendar"

    /// The OAuth loopback flow for installed apps, with PKCE. Hands `onURL` the consent link, waits on
    /// 127.0.0.1 for Google's redirect, exchanges the code and saves the login, replacing any other.
    /// Cancelling or timing out closes the port.
    public static func run(
        client: GoogleClient, timeout: Duration, onURL: @escaping @Sendable (URL) -> Void
    ) async throws {
        let verifier = randomString()
        let state = randomString()
        let server = try await LoopbackServer.start()
        defer { server.stop() }
        let redirect = "http://127.0.0.1:\(server.port)"
        onURL(authURL(client: client, redirect: redirect, challenge: challenge(for: verifier), state: state))

        let code = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await code(from: server, state: state) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw GoogleLoginError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        server.stop()

        let token = try await GoogleOAuth.requestToken(
            [
                "grant_type": "authorization_code",
                "code": code,
                "code_verifier": verifier,
                "redirect_uri": redirect,
                "client_id": client.clientID,
                "client_secret": client.clientSecret,
            ], send: urlSessionSend)
        guard let refreshToken = token.refreshToken else { throw GoogleLoginError.noRefreshToken }
        let credentials = GoogleCredentials(
            clientID: client.clientID, clientSecret: client.clientSecret, refreshToken: refreshToken)
        try GoogleKeychain.save(credentials, scopes: token.scope?.split(separator: " ").map(String.init) ?? [])
        await GoogleAuth.shared.loggedIn(credentials, accessToken: token.accessToken, expiresIn: token.expiresIn)
    }

    /// `access_type=offline` and `prompt=consent`, so a refresh token always comes back.
    static func authURL(client: GoogleClient, redirect: String, challenge: String, state: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: client.clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url!
    }

    /// PKCE's S256 challenge (RFC 7636).
    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func randomString() -> String {
        base64URL(Data(SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Answers every request, and returns the code from the one carrying this login's `state`.
    private static func code(from server: LoopbackServer, state: String) async throws -> String {
        for await request in server.requests {
            guard let query = request.redirectQuery else {
                request.respond("404 Not Found", "Not found.")
                continue
            }
            func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
            guard value("state") == state else {
                request.respond("400 Bad Request", "This login is out of date. Start it again from Captain's Log.")
                continue
            }
            if let error = value("error") {
                request.respond("200 OK", "The login didn't finish. You can close this tab.")
                throw GoogleLoginError.denied(error)
            }
            guard let code = value("code") else {
                request.respond("400 Bad Request", "Google didn't send a code. Start the login again from Captain's Log.")
                continue
            }
            request.respond("200 OK", "Logged in to Google Calendar. You can close this tab and go back to Captain's Log.")
            return code
        }
        throw CancellationError()
    }
}

/// An HTTP listener on 127.0.0.1, on a free port, for Google's redirect. Reads each request's headers
/// and keeps the first line: closing with headers unread can reset the connection before the page
/// shows. Iterating `requests` ends when the task is cancelled, which closes the port.
private final class LoopbackServer: Sendable {
    let port: UInt16
    let requests: AsyncStream<LoopbackRequest>
    private let listener: NWListener
    private let continuation: AsyncStream<LoopbackRequest>.Continuation

    private static let queue = DispatchQueue(label: "com.nindalf.captainslog.google-login")

    private init(port: UInt16, listener: NWListener, requests: AsyncStream<LoopbackRequest>, continuation: AsyncStream<LoopbackRequest>.Continuation) {
        self.port = port
        self.listener = listener
        self.requests = requests
        self.continuation = continuation
    }

    static func start() async throws -> LoopbackServer {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        let (requests, continuation) = AsyncStream.makeStream(of: LoopbackRequest.self, bufferingPolicy: .bufferingNewest(8))
        continuation.onTermination = { _ in listener.cancel() }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            readRequestHead(connection) { line in
                if case .terminated = continuation.yield(LoopbackRequest(line: line, connection: connection)) {
                    connection.cancel()
                }
            }
        }
        let port = try await withCheckedThrowingContinuation { (ready: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    ready.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    ready.resume(throwing: error)
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    ready.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        return LoopbackServer(port: port, listener: listener, requests: requests, continuation: continuation)
    }

    func stop() {
        continuation.finish()
        listener.cancel()
    }

    private static func readRequestHead(
        _ connection: NWConnection, received: Data = Data(), then deliver: @escaping @Sendable (String) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
            let received = received + (data ?? Data())
            if received.firstRange(of: Data("\r\n\r\n".utf8)) != nil,
                let lineEnd = received.firstRange(of: Data("\r\n".utf8))
            {
                deliver(String(decoding: received[..<lineEnd.lowerBound], as: UTF8.self))
            } else if error == nil, !isComplete, received.count < 16 * 1024 {
                readRequestHead(connection, received: received, then: deliver)
            } else {
                connection.cancel()
            }
        }
    }
}

private struct LoopbackRequest: Sendable {
    let line: String
    let connection: NWConnection

    /// The query of a GET to the root, which is where Google redirects.
    var redirectQuery: [URLQueryItem]? {
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", let components = URLComponents(string: String(parts[1])),
            components.path == "/"
        else { return nil }
        return components.queryItems ?? []
    }

    func respond(_ status: String, _ message: String) {
        let body = """
            <!doctype html><meta charset="utf-8"><title>Captain's Log</title>\
            <p style="font: 15px -apple-system, sans-serif; margin: 3em">\(message)</p>
            """
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
