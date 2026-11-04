import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

struct Sync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync data from external sources"
    )

    @Option(name: .long, parsing: .upToNextOption, help: "GitHub repos to sync (e.g. your-org/your-repo)")
    var repos: [String] = []

    @Option(name: .long, parsing: .upToNextOption, help: "Calendar names to include")
    var calendars: [String] = []

    @Flag(name: .long, help: "Sync GitHub PRs")
    var github: Bool = false

    @Flag(name: .long, help: "Sync calendar events")
    var calendar: Bool = false

    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false

    mutating func run() async throws {
        let syncAll = !github && !calendar

        let container = try Store.makeContainer()
        var results: [String: String] = [:]

        if github || syncAll {
            let settings = AppSettings()
            let repoList = repos.isEmpty ? settings.repos : repos

            if repoList.isEmpty {
                FileHandle.standardError.write(Data("No repos specified. Use --repos or configure in settings.\n".utf8))
            } else {
                let actor = GitHubSync(modelContainer: container)
                do {
                    try await actor.sync(repos: repoList, skipUpdatedBefore: settings.retention.pullRequests.cutoff())
                    SyncHistory.update { $0.recordSuccess(.github) }
                } catch {
                    SyncHistory.update { $0.recordFailure(.github, error: error.localizedDescription) }
                    throw error
                }

                let context = ModelContext(container)
                let prCount = try context.fetchCount(FetchDescriptor<PullRequest>())
                results["github"] = "synced \(repoList.count) repo(s), \(prCount) total PRs in store"
            }
        }

        if calendar || syncAll {
            let settings = AppSettings()
            let calList = calendars.isEmpty ? settings.calendarAllowlist : calendars

            let actor = CalendarSync(modelContainer: container)
            do {
                try await actor.sync(calendarAllowlist: calList, weeksAhead: settings.calendarFetchWeeks)
                SyncHistory.update { $0.recordSuccess(.calendar) }
            } catch {
                SyncHistory.update { $0.recordFailure(.calendar, error: error.localizedDescription) }
                throw error
            }

            let context = ModelContext(container)
            let eventCount = try context.fetchCount(FetchDescriptor<CalendarEvent>())
            results["calendar"] = "synced, \(eventCount) total events in store"
        }

        try printJSON(results, pretty: pretty)
    }
}
