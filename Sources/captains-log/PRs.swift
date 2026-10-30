import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

struct PRs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prs",
        abstract: "Manage pull requests",
        subcommands: [List.self, Edit.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List pull requests, newest first"
        )

        @Option(name: .long, help: "Filter by state: open, merged, closed")
        var state: String?

        @Flag(name: .long, help: "Show only PRs authored by me")
        var mine: Bool = false

        @Flag(name: .long, help: "Show only PRs awaiting my review")
        var reviews: Bool = false

        @Flag(name: .long, help: "Show only PRs synced because their author's PRs are (people edit --sync-prs), never asking for my review")
        var teammates: Bool = false

        @Flag(name: .long, help: "Show only PRs I've reviewed, on any request, mine or a team's. --from and --to then go by my latest review")
        var reviewed: Bool = false

        @Option(name: .long, help: "Only PRs created or merged on or after this date (ISO 8601, e.g. 2026-04-28)")
        var from: String?

        @Option(name: .long, help: "Only PRs created or merged on or before this date, inclusive")
        var to: String?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            if [mine, reviews, teammates, reviewed].filter({ $0 }).count > 1 {
                throw ValidationError("Only one of --mine, --reviews, --teammates and --reviewed")
            }
        }

        mutating func run() async throws {
            if let state, PRState(rawValue: state) == nil {
                throw ValidationError("Invalid state '\(state)'. Use: open, merged, closed")
            }

            // Unlike other lists, no default range: `--state open` means every open PR.
            let range = from == nil && to == nil ? nil
                : try CLIDate.range(from: from, to: to, defaultFrom: .distantPast, defaultTo: .distantFuture)

            let container = try Store.makeContainer()
            let context = ModelContext(container)

            let descriptor = FetchDescriptor<PullRequest>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            // Filtered in Swift so the flags combine; one predicate per flag would overwrite the last.
            let wanted = state.flatMap(PRState.init(rawValue:))
            let prs = try context.fetch(descriptor).filter { pr in
                if mine && !pr.isAuthoredByMe { return false }
                if reviews && (!pr.isReviewRequest || pr.state != .open) { return false }
                if teammates && !pr.isTeammateOnly { return false }
                if let wanted, pr.state != wanted { return false }
                if reviewed {
                    guard let reviewedAt = pr.myReviewedAt else { return false }
                    if let range, !range.contains(reviewedAt) { return false }
                } else if let range, !range.contains(pr.createdAt), !(pr.mergedAt.map(range.contains) ?? false) {
                    return false
                }
                return true
            }

            try printJSON(prs.map(PullRequestDTO.from), pretty: pretty)
        }
    }

    struct Edit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Change a PR's notes. Everything else comes from GitHub sync",
            discussion: "An empty value clears the notes. Pass - to read them from stdin."
        )

        @Argument(help: "Pull request UUID")
        var id: String

        @Option(name: .long, help: "Notes (markdown)")
        var notes: String?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            if notes == nil {
                throw ValidationError("Nothing to change")
            }
        }

        mutating func run() async throws {
            let notes = try TextInput.resolve([notes])[0]
            let context = ModelContext(try Store.makeContainer())
            let pr = try PRs.pullRequest(id: id, in: context)
            if let notes { pr.notes = TextInput.field(notes) }
            try context.save()

            try printJSON(PullRequestDTO.from(pr), pretty: pretty)
        }
    }

    static func pullRequest(id: String, in context: ModelContext) throws -> PullRequest {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("Invalid UUID: \(id)")
        }
        guard let pr = try context.fetch(FetchDescriptor<PullRequest>(predicate: #Predicate { $0.id == uuid })).first else {
            throw ValidationError("Pull request not found: \(id)")
        }
        return pr
    }
}
