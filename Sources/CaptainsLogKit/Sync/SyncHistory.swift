import Foundation
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "sync")

public enum SyncError: Error, LocalizedError {
    /// Some items failed; the rest were saved.
    case partial([String])

    public var errorDescription: String? {
        switch self {
        case .partial(let failures): failures.joined(separator: "; ")
        }
    }
}

// CodingKeyRepresentable makes `[SyncSource: Entry]` encode as a JSON object, not a flat array.
public enum SyncSource: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case github, calendar, backup
}

/// When each sync source last succeeded and last failed, so the CLI can tell how fresh the store is.
/// Kept in a JSON file beside the store rather than in UserDefaults, so a scratch store's syncs
/// never pass for the real store's.
public struct SyncHistory: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var lastSuccess: Date?
        public var lastFailure: Date?
        public var lastError: String?

        public init(lastSuccess: Date? = nil, lastFailure: Date? = nil, lastError: String? = nil) {
            self.lastSuccess = lastSuccess
            self.lastFailure = lastFailure
            self.lastError = lastError
        }

        /// The most recent attempt failed.
        public var isFailing: Bool {
            guard let lastFailure else { return false }
            return lastSuccess.map { lastFailure > $0 } ?? true
        }

        public func syncedToday(now: Date = .now, calendar: Calendar = .current) -> Bool {
            lastSuccess.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        }
    }

    public var sources: [SyncSource: Entry] = [:]

    public init() {}

    public mutating func recordSuccess(_ source: SyncSource, at date: Date = .now) {
        sources[source, default: Entry()].lastSuccess = date
    }

    public mutating func recordFailure(_ source: SyncSource, error: String, at date: Date = .now) {
        sources[source, default: Entry()].lastFailure = date
        sources[source, default: Entry()].lastError = error
    }

    // MARK: - File

    public static var fileURL: URL { Store.directory.appending(path: "sync-history.json") }

    /// The recorded history, or an empty one when nothing has synced yet or the file is unreadable.
    public static func load() -> SyncHistory {
        guard let data = try? Data(contentsOf: fileURL) else { return SyncHistory() }
        do {
            return try decoder.decode(SyncHistory.self, from: data)
        } catch {
            logger.error("Unreadable sync history, starting afresh: \(error)")
            return SyncHistory()
        }
    }

    /// Reloads, applies `change` and writes back, so the app and the CLI don't drop each other's entries.
    /// Failing to record is logged rather than thrown: it mustn't fail the sync itself.
    public static func update(_ change: (inout SyncHistory) -> Void) {
        var history = load()
        change(&history)
        do {
            try FileManager.default.createDirectory(at: Store.directory, withIntermediateDirectories: true)
            try encoder.encode(history).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Couldn't record sync history: \(error)")
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
