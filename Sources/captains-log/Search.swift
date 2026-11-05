import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search people, projects, todos, log entries, meetings, interviews, PRs and feedback",
        discussion: """
            Every word must appear somewhere in the record. Each result says which field matched best and \
            shows the text around the match. A private record matches on its title alone. Undated results (people, open projects and todos) come first, then newest first.
            """
    )

    @Argument(help: "Search query")
    var query: String

    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false

    mutating func run() async throws {
        guard !SearchMatch.terms(of: query).isEmpty else {
            throw ValidationError("Search query can't be empty")
        }
        let context = ModelContext(try Store.makeContainer())
        let results = try Searcher.search(query, in: context, privateTitlesOnly: true).map {
            SearchResultDTO($0)
        }
        try printJSON(results, pretty: pretty)
    }
}
