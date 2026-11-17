import Foundation
import Testing
import CaptainsLogKit

// What an open PR needs from me, and whether CI's blocking checks passed. Models are never inserted.
@Suite(.serialized) @MainActor
struct PRAttentionTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Tuesday 17 November 2026, 10:00 UTC.
    private let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10))!

    private func hoursAgo(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

    private func pr(mine: Bool, requestedHoursAgo: Double = 1) -> PullRequest {
        let pr = PullRequest(
            number: 7, title: "Add retries", url: URL(string: "https://github.com/larder/fulfilment/pull/7")!,
            repo: "larder/fulfilment", state: .open, createdAt: hoursAgo(200), isAuthoredByMe: mine
        )
        if !mine { pr.isTeammateOnly = true }
        pr.ciStatus = .passing
        pr.reviewDecision = .reviewRequired
        pr.reviewRequestedAt = hoursAgo(requestedHoursAgo)
        return pr
    }

    private func attention(_ pr: PullRequest) -> PRAttention { pr.attention(now: now, calendar: Self.calendar) }

    // MARK: My PRs

    @Test func aConflictOutranksFailingCI() {
        let mine = pr(mine: true)
        mine.ciStatus = .failing
        #expect(attention(mine) == .ciFailing)
        mine.hasConflicts = true
        #expect(attention(mine) == .conflict)
    }

    @Test func anApprovedPRIsReadyUnlessCIOrAutoMergeIsStillGoing() {
        let mine = pr(mine: true)
        mine.reviewDecision = .approved
        mine.reviewStatus = .approved
        #expect(attention(mine) == .readyToMerge)
        #expect(attention(mine).section == .needsMe)

        mine.ciStatus = .pending
        #expect(attention(mine) == .ciPending)
        mine.isAutoMergeEnabled = true
        #expect(attention(mine) == .autoMerge)
        #expect(attention(mine).section == .waiting)
    }

    @Test func changesRequestedNeedsMeUntilIPush() {
        let mine = pr(mine: true)
        mine.reviewStatus = .changesRequested
        #expect(attention(mine) == .changesRequested)

        mine.reviewStatus = .changesRequestedEarlier
        #expect(attention(mine) == .awaitingReview(isStale: false))
    }

    @Test func aDismissedApprovalNeedsMeUnlessGitHubStillCountsIt() {
        let mine = pr(mine: true)
        mine.reviewStatus = .approvalDismissed
        #expect(attention(mine) == .approvalDismissed)

        // As on a repo that keeps approvals across pushes.
        mine.reviewDecision = .approved
        #expect(attention(mine) == .readyToMerge)
    }

    @Test func anApprovalStillShortOfTheRulesWaitsForMore() {
        let mine = pr(mine: true)
        mine.reviewStatus = .approved
        #expect(attention(mine) == .moreApprovalsNeeded)
        #expect(attention(mine).section == .waiting)
    }

    @Test func withoutReviewRulesAnApprovalIsEnough() {
        let mine = pr(mine: true)
        mine.reviewDecision = nil
        mine.reviewStatus = .approved
        #expect(attention(mine) == .readyToMerge)
    }

    @Test func aReviewRequestGoesStaleAfterTwoWorkingDays() {
        // Requested Friday 13 November 10:00: two working days on is Tuesday 10:00.
        let friday = pr(mine: true, requestedHoursAgo: 4 * 24)
        #expect(attention(friday) == .awaitingReview(isStale: true))

        // Requested Monday 09:00: stale from Wednesday 09:00.
        let monday = pr(mine: true, requestedHoursAgo: 25)
        #expect(attention(monday) == .awaitingReview(isStale: false))

        let reviewed = pr(mine: true, requestedHoursAgo: 4 * 24)
        reviewed.lastReviewedAt = hoursAgo(24)
        #expect(attention(reviewed) == .awaitingReview(isStale: false))

        // A review from before it last asked doesn't count.
        reviewed.lastReviewedAt = hoursAgo(5 * 24)
        #expect(attention(reviewed) == .awaitingReview(isStale: true))
    }

    @Test func aDraftIsWaiting() {
        let mine = pr(mine: true)
        mine.isDraft = true
        mine.ciStatus = .failing
        #expect(attention(mine) == .draft)
        #expect(attention(mine).section == .waiting)
    }

    // MARK: Others' PRs

    @Test func aRequestFromMeNeedsMyReview() {
        let theirs = pr(mine: false)
        theirs.isReviewRequestedFromMe = true
        #expect(attention(theirs) == .reviewRequested)

        theirs.myReviewedAt = hoursAgo(30)
        #expect(attention(theirs) == .reReview)
    }

    @Test func aPushAfterMyChangesRequestNeedsMyReviewAgain() {
        let theirs = pr(mine: false)
        #expect(attention(theirs) == .inFlight(isStale: false))
        theirs.myReviewIsOutdated = true
        #expect(attention(theirs) == .reReview)
    }

    @Test func aTeammatesUnreviewedPRGoesStale() {
        let theirs = pr(mine: false, requestedHoursAgo: 5 * 24)
        #expect(attention(theirs) == .inFlight(isStale: true))
        theirs.isDraft = true
        #expect(attention(theirs) == .inFlight(isStale: false))
    }

    @Test func mergedAndClosedAreDone() {
        let merged = pr(mine: true)
        merged.state = .merged
        #expect(attention(merged) == .merged)
        merged.state = .closed
        #expect(attention(merged) == .closed)
        #expect(attention(merged).section == .done)
    }

    // MARK: CI

    private let required: Set<String> = ["test-summary", "Passed"]

    @Test func aNonBlockingFailureDoesNotFailCI() {
        let status = CIRollup.evaluate(checks: [
            CICheck(name: "test-summary", isRequired: true, result: .passed),
            CICheck(name: "Passed", isRequired: true, result: .passed),
            CICheck(name: "poll-test-non-blocking", isRequired: false, result: .failed),
        ], required: required, rollupState: "FAILURE")
        #expect(status == .passing)
    }

    @Test func aRequiredFailureFailsCI() {
        let status = CIRollup.evaluate(checks: [
            CICheck(name: "test-summary", isRequired: true, result: .failed),
            CICheck(name: "Passed", isRequired: true, result: .pending),
        ], required: required, rollupState: "FAILURE")
        #expect(status == .failing)
    }

    @Test func aRequiredCheckNotYetStartedIsPending() {
        let status = CIRollup.evaluate(checks: [
            CICheck(name: "test-summary", isRequired: true, result: .passed),
        ], required: required, rollupState: "SUCCESS")
        #expect(status == .pending)
    }

    @Test func theLatestRunOfACheckCounts() {
        let earlier = now.addingTimeInterval(-600)
        let status = CIRollup.evaluate(checks: [
            CICheck(name: "test-summary", isRequired: true, result: .passed, startedAt: now),
            CICheck(name: "test-summary", isRequired: true, result: .failed, startedAt: earlier),
            CICheck(name: "Passed", isRequired: true, result: .passed),
        ], required: required, rollupState: "FAILURE")
        #expect(status == .passing)
    }

    @Test func aCheckGitHubMarksRequiredCountsWithoutTheRules() {
        let status = CIRollup.evaluate(checks: [
            CICheck(name: "test-summary", isRequired: true, result: .failed),
        ], required: [], rollupState: "SUCCESS")
        #expect(status == .failing)
    }

    @Test func withNothingRequiredTheRollupDecides() {
        let checks = [CICheck(name: "lint", isRequired: false, result: .failed)]
        #expect(CIRollup.evaluate(checks: checks, required: [], rollupState: "FAILURE") == .failing)
        #expect(CIRollup.evaluate(checks: [], required: [], rollupState: nil) == .unknown)
    }
}
