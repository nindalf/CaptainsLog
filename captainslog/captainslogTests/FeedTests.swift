import Foundation
import Testing
import CaptainsLogKit

// What the Log tab and `captains-log feed` list. Models are never inserted.
@Suite(.serialized) @MainActor
struct FeedTests {
    private func pr(_ state: PRState, mine: Bool = true) -> PullRequest {
        PullRequest(
            number: 7, title: "Add retries", url: URL(string: "https://github.com/larder/fulfilment/pull/7")!,
            repo: "larder/fulfilment", state: state, createdAt: .now, isAuthoredByMe: mine
        )
    }

    @Test func onlyMyMergedPRsAreInTheLog() {
        #expect(Feed.includes(pr(.merged)))
        // Open ones are on the Pull Requests tab; closed ones never shipped.
        #expect(!Feed.includes(pr(.open)))
        #expect(!Feed.includes(pr(.closed)))
        #expect(!Feed.includes(pr(.merged, mine: false)))
    }
}
