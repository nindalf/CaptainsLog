import Foundation
import Security

/// Everything a refresh needs, so the CLI can refresh without finding the app's `GoogleClient.json`.
public struct GoogleCredentials: Codable, Sendable, Equatable {
    public let clientID: String
    public let clientSecret: String
    public let refreshToken: String

    public init(clientID: String, clientSecret: String, refreshToken: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.refreshToken = refreshToken
    }
}

/// The Google login, as a legacy keychain item: the data-protection keychain shares items only through
/// entitlements a bare CLI binary can't carry. Its access list names the app and its bundled CLI by code
/// signature, so a Developer ID build of either reads it without a prompt, across upgrades; any other
/// binary, a rebuilt ad hoc one included, gets the Keychain's prompt.
enum GoogleKeychain {
    /// A sandbox logs in to an item of its own, so trying the login there never replaces the real one.
    private static var service: String { "com.nindalf.captainslog.google" + (Store.isScratch ? ".scratch" : "") }
    private static let account = "calendar"

    private static func query(_ service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: false,
        ]
    }

    /// The scopes the login was granted, nil when logged out. Reads only the item's attributes, which
    /// its access list doesn't cover, so it never prompts and needs no network.
    static func grantedScopes() throws -> [String]? {
        var query = query(service)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let attributes = result as? [String: Any] else {
            throw GoogleAuthError.keychain(status)
        }
        let scopes = (attributes[kSecAttrGeneric as String] as? Data).map { String(decoding: $0, as: UTF8.self) }
        return scopes?.split(separator: " ").map(String.init) ?? []
    }

    static func load() throws -> GoogleCredentials? {
        var query = query(service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw GoogleAuthError.keychain(status) }
        return try JSONDecoder().decode(GoogleCredentials.self, from: data)
    }

    /// Replaces any earlier login, with a fresh access list naming the binaries that run now.
    static func save(_ credentials: GoogleCredentials, scopes: [String]) throws {
        try delete()
        var item = query(service)
        item[kSecValueData as String] = try JSONEncoder().encode(credentials)
        item[kSecAttrGeneric as String] = Data(scopes.joined(separator: " ").utf8)
        item[kSecAttrLabel as String] = "Captain's Log: Google Calendar"
        item[kSecAttrAccess as String] = try access()
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw GoogleAuthError.keychain(status) }
    }

    static func delete() throws {
        let status = SecItemDelete(query(service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw GoogleAuthError.keychain(status) }
    }

    /// This binary, and the CLI in `Contents/Helpers` when this is the app. Debug builds have no CLI there.
    private static func access() throws -> SecAccess {
        let cli = Bundle.main.bundleURL.appending(path: "Contents/Helpers/captains-log").path(percentEncoded: false)
        let paths: [String?] = FileManager.default.isExecutableFile(atPath: cli) ? [nil, cli] : [nil]
        return try (LegacyAccess() as LegacyAccessMaking).make(label: "Captain's Log: Google Calendar", trusting: paths)
    }
}

/// `SecAccess` is deprecated, with no replacement for a legacy item's access list. Calling it through a
/// protocol keeps the deprecation warnings to this one place.
private protocol LegacyAccessMaking {
    func make(label: String, trusting paths: [String?]) throws -> SecAccess
}

private struct LegacyAccess: LegacyAccessMaking {
    @available(macOS, deprecated: 10.10)
    func make(label: String, trusting paths: [String?]) throws -> SecAccess {
        var apps: [SecTrustedApplication] = []
        for path in paths {
            var app: SecTrustedApplication?
            let status = SecTrustedApplicationCreateFromPath(path, &app)
            guard status == errSecSuccess, let app else { throw GoogleAuthError.keychain(status) }
            apps.append(app)
        }
        var access: SecAccess?
        let status = SecAccessCreate(label as CFString, apps as CFArray, &access)
        guard status == errSecSuccess, let access else { throw GoogleAuthError.keychain(status) }
        return access
    }
}
