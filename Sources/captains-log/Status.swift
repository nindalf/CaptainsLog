import ArgumentParser
import CaptainsLogKit
import Foundation

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "When each source last synced, so you know how fresh the store is",
        discussion: "Sources are GitHub, the calendar and backup (the app's daily encrypted backup; `just backup` by hand doesn't count). Syncs by the app and by captains-log sync both count."
    )

    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false

    mutating func run() async throws {
        let history = SyncHistory.load()
        var sources: [String: SourceStatus] = [:]
        for source in SyncSource.allCases {
            let entry = history.sources[source] ?? SyncHistory.Entry()
            sources[source.rawValue] = SourceStatus(
                lastSuccess: entry.lastSuccess,
                syncedToday: entry.syncedToday(),
                lastFailure: entry.lastFailure,
                lastError: entry.lastError,
                isFailing: entry.isFailing
            )
        }
        try printJSON(StatusDTO(store: Store.directory.path(percentEncoded: false), isScratch: Store.isScratch, sync: sources), pretty: pretty)
    }

    struct StatusDTO: Encodable {
        let store: String
        let isScratch: Bool
        let sync: [String: SourceStatus]
    }

    struct SourceStatus: Encodable {
        let lastSuccess: Date?
        let syncedToday: Bool
        let lastFailure: Date?
        let lastError: String?
        let isFailing: Bool
    }
}
