import Foundation
import Testing
import CaptainsLogKit

// Which section a synced PR lands in, whatever order the fetches find it. Models are never inserted.
@Suite(.serialized) @MainActor
struct PRSyncSourceTests {
    private func pr(_ source: PRSyncSource) -> PullRequest {
        let pr = PullRequest(
            number: 7, title: "Add retries", url: URL(string: "https://github.com/larder/fulfilment/pull/7")!,
            repo: "larder/fulfilment", state: .open, createdAt: .now, isAuthoredByMe: source == .mine
        )
        pr.applySyncSource(source, isNew: true)
        return pr
    }

    @Test func aTeammatesPRIsNotAReviewRequest() {
        let teammate = pr(.teammate)
        #expect(teammate.isTeammateOnly)
        #expect(!teammate.isReviewRequest)
        #expect(!teammate.isAuthoredByMe)
    }

    @Test func aReviewRequestWinsOverTheTeammateFetch() {
        let found = pr(.teammate)
        found.applySyncSource(.reviewRequest, isNew: false)
        #expect(found.isReviewRequest)

        let requested = pr(.reviewRequest)
        requested.applySyncSource(.teammate, isNew: false)
        #expect(requested.isReviewRequest)
        #expect(!requested.isTeammateOnly)
    }

    @Test func aPRIReviewedOnATeamRequestIsATeammates() {
        let reviewed = pr(.reviewedByMe)
        #expect(reviewed.isTeammateOnly)
        #expect(!reviewed.isReviewRequest)
    }

    @Test func theReviewedFetchKeepsAReviewRequestAndMyOwnPR() {
        let requested = pr(.reviewRequest)
        requested.applySyncSource(.reviewedByMe, isNew: false)
        #expect(requested.isReviewRequest)

        let found = pr(.reviewedByMe)
        found.applySyncSource(.reviewRequest, isNew: false)
        #expect(found.isReviewRequest)

        let mine = pr(.mine)
        mine.applySyncSource(.reviewedByMe, isNew: false)
        #expect(mine.isAuthoredByMe)
        #expect(!mine.isTeammateOnly)
    }

    @Test func aRecheckKeepsTheFlags() {
        let teammate = pr(.teammate)
        teammate.applySyncSource(.recheck, isNew: false)
        #expect(teammate.isTeammateOnly)

        let requested = pr(.reviewRequest)
        requested.applySyncSource(.recheck, isNew: false)
        #expect(requested.isReviewRequest)
    }

    @Test func myOwnPRIsNeitherWhenAlsoFetchedAsATeammates() {
        let mine = pr(.mine)
        mine.applySyncSource(.teammate, isNew: false)
        #expect(mine.isAuthoredByMe)
        #expect(!mine.isTeammateOnly)
        #expect(!mine.isReviewRequest)
    }
}
