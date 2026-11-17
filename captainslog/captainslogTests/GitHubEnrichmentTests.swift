import Foundation
import Testing
@testable import CaptainsLogKit

// Decoding what GitHub returns for open PRs' details, from trimmed real responses.
struct GitHubEnrichmentTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func requiredChecksComeFromTheRulesetsRule() throws {
        let rules = """
        [{"type": "pull_request", "parameters": {"required_approving_review_count": 1}},
         {"type": "required_status_checks", "parameters": {"required_status_checks": [
            {"context": "test-summary", "integration_id": 15368}, {"context": "Passed"}]}},
         {"type": "deletion"}]
        """
        #expect(try decodeRequiredChecks(Data(rules.utf8)) == ["test-summary", "Passed"])
    }

    @Test func checkConclusionsMapToPassFailOrPending() throws {
        func result(_ json: String) throws -> CICheck.Result? {
            try decode(GQLCheckContext.self, json).check?.result
        }
        #expect(try result(#"{"name": "a", "status": "COMPLETED", "conclusion": "SKIPPED"}"#) == .passed)
        #expect(try result(#"{"name": "a", "status": "COMPLETED", "conclusion": "NEUTRAL"}"#) == .passed)
        #expect(try result(#"{"name": "a", "status": "COMPLETED", "conclusion": "CANCELLED"}"#) == .failed)
        #expect(try result(#"{"name": "a", "status": "COMPLETED", "conclusion": "STALE"}"#) == .failed)
        #expect(try result(#"{"name": "a", "status": "IN_PROGRESS", "conclusion": null}"#) == .pending)
        #expect(try result(#"{"context": "ci/legacy", "state": "EXPECTED"}"#) == .pending)
        #expect(try result(#"{"context": "ci/legacy", "state": "ERROR"}"#) == .failed)
    }

    @Test func aMissingPRIsDroppedAndOtherErrorsReported() throws {
        let response = """
        {"data": {"repository": {
            "p1": {"number": 1, "commits": {"nodes": []}},
            "p2": null,
            "p3": null}},
         "errors": [
            {"type": "NOT_FOUND", "message": "Could not resolve to a PullRequest with the number of 2."},
            {"type": "RESOURCE_LIMITS_EXCEEDED", "message": "Resource limits exceeded for p3."}]}
        """
        let result = try decodeEnrichment(stdout: Data(response.utf8), exitCode: 1, stderr: "")
        #expect(Array(result.prs.keys) == ["p1"])
        #expect(result.errors == ["Resource limits exceeded for p3."])
    }

    @Test func noDataThrowsWithWhatGhSaid() {
        let error = #expect(throws: ProcessError.self) {
            try decodeEnrichment(stdout: Data(#"{"message": "Bad credentials"}"#.utf8), exitCode: 1, stderr: "HTTP 401: Bad credentials")
        }
        guard case .nonZeroExit(_, let stderr) = error else { Issue.record("expected a non-zero exit"); return }
        #expect(stderr == "HTTP 401: Bad credentials")
    }

    // MARK: Reviews

    private func reviews(_ json: String) throws -> [GQLReview] { try decode([GQLReview].self, json) }

    @Test func aCommentAfterAnApprovalKeepsTheApprovalButCountsAsReviewing() throws {
        let latest = try reviews("""
        [{"author": {"__typename": "User", "login": "kyle"}, "state": "COMMENTED",
          "submittedAt": "2026-11-17T12:00:00Z", "commit": {"oid": "head"}}]
        """)
        let opinionated = try reviews("""
        [{"author": {"__typename": "User", "login": "kyle"}, "state": "APPROVED",
          "submittedAt": "2026-11-17T09:00:00Z", "commit": {"oid": "older"}}]
        """)
        #expect(mergeReviews(latest: latest, opinionated: opinionated) == [
            ReviewSnapshot(login: "kyle", state: "APPROVED", commitOID: "older", submittedAt: parseISO8601("2026-11-17T12:00:00Z")),
        ])
    }

    @Test func aDismissalOutranksAnEarlierOpinion() throws {
        let latest = try reviews("""
        [{"author": {"__typename": "User", "login": "kyle"}, "state": "DISMISSED", "commit": {"oid": "newer"}}]
        """)
        let opinionated = try reviews("""
        [{"author": {"__typename": "User", "login": "kyle"}, "state": "CHANGES_REQUESTED", "commit": {"oid": "older"}}]
        """)
        #expect(mergeReviews(latest: latest, opinionated: opinionated) == [
            ReviewSnapshot(login: "kyle", state: "DISMISSED", commitOID: "newer"),
        ])
    }

    @Test func botsAreLeftOut() throws {
        let latest = try reviews("""
        [{"author": {"__typename": "Bot", "login": "copilot"}, "state": "COMMENTED"},
         {"author": {"__typename": "User", "login": "kyle"}, "state": "COMMENTED"}]
        """)
        #expect(mergeReviews(latest: latest, opinionated: []).map(\.login) == ["kyle"])
    }

    private let noon = parseISO8601("2026-11-17T12:00:00Z")!

    private func summary(
        _ reviews: [ReviewSnapshot], author: String = "ben", isMine: Bool = false, decision: String = "REVIEW_REQUIRED"
    ) -> ReviewSummary {
        summarizeReviews(reviews, head: "head", author: author, myLogin: "me", isMine: isMine, decision: decision)
    }

    private func review(_ state: String, by login: String = "kyle", on commit: String = "head", at date: Date? = nil) -> ReviewSnapshot {
        ReviewSnapshot(login: login, state: state, commitOID: commit, submittedAt: date)
    }

    @Test func aChangeRequestOnTheHeadOutranksEverything() {
        #expect(summary([review("APPROVED", by: "aisha"), review("DISMISSED", by: "li"), review("CHANGES_REQUESTED")]).status == .changesRequested)
    }

    @Test func aPushPastAChangeRequestWaitsForAnotherLook() {
        #expect(summary([review("CHANGES_REQUESTED", on: "older")]).status == .changesRequestedEarlier)
        // Someone else's approval doesn't lift it.
        #expect(summary([review("CHANGES_REQUESTED", on: "older"), review("APPROVED", by: "aisha")]).status == .changesRequestedEarlier)
    }

    @Test func anApprovalOnAnOlderCommitReadsAsDismissed() {
        #expect(summary([review("APPROVED", on: "older")]).status == .approvalDismissed)
        #expect(summary([review("DISMISSED")]).status == .approvalDismissed)
        #expect(summary([review("APPROVED")]).status == .approved)
    }

    @Test func theDecisionSaysChangesRequestedWhenNoReviewShowsIt() {
        #expect(summary([], decision: "CHANGES_REQUESTED").status == .changesRequested)
        #expect(summary([]).status == .unreviewed)
    }

    @Test func myOwnReviewsAndTheAuthorsDontDecideTheStatus() {
        #expect(summary([review("CHANGES_REQUESTED", by: "me"), review("COMMENTED", by: "ben")]).status == .unreviewed)
    }

    @Test func myChangeRequestIsOutdatedOnceTheyPush() {
        #expect(summary([review("CHANGES_REQUESTED", by: "Me", on: "older")]).myReviewIsOutdated)
        #expect(!summary([review("CHANGES_REQUESTED", by: "me")]).myReviewIsOutdated)
        #expect(!summary([review("APPROVED", by: "me", on: "older")]).myReviewIsOutdated)
    }

    @Test func theAuthorsRepliesAndMineOnMyPRDontCountAsReviewing() {
        let replies = [review("COMMENTED", by: "ben", at: noon), review("COMMENTED", by: "me", at: noon)]
        #expect(summary(replies).lastReviewedAt == noon)
        #expect(summary(replies, author: "me", isMine: true).lastReviewedAt == noon)
        #expect(summary([review("COMMENTED", by: "me", at: noon)], author: "agent", isMine: true).lastReviewedAt == nil)
    }
}
