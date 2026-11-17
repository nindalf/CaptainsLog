import Foundation

/// What a PR needs from me, or where it stands if nothing. One that matches several gets the
/// first in this order, but a draft is a draft whatever else holds.
public enum PRAttention: Equatable, Sendable {
    // My PRs that need me.
    case conflict, ciFailing
    /// On the head commit: once I push, it waits for the reviewer again.
    case changesRequested
    /// Pushed to since its approval, or a review was dismissed.
    case approvalDismissed
    case readyToMerge
    // Others' PRs that need me.
    case reviewRequested, reReview
    // My PRs waiting on someone or something else.
    case draft, autoMerge, ciPending
    /// Approved, but the review rules want more, such as a code owner's.
    case moreApprovalsNeeded
    case awaitingReview(isStale: Bool)
    /// Someone else's open PR that needs nothing from me.
    case inFlight(isStale: Bool)
    case merged, closed

    public enum Section: Sendable { case needsMe, waiting, inFlight, done }

    /// A PR waiting this long for a first review since it asked for one is stale.
    public static let staleAfterWorkingDays = 2

    /// Order within Needs You: what blocks my own PR, then reviews I owe, then merging.
    public var urgency: Int {
        switch self {
        case .conflict: 0
        case .ciFailing: 1
        case .changesRequested: 2
        case .approvalDismissed: 3
        case .reReview: 4
        case .reviewRequested: 5
        case .readyToMerge: 6
        case .draft, .autoMerge, .ciPending, .moreApprovalsNeeded, .awaitingReview, .inFlight, .merged, .closed: 7
        }
    }

    public var section: Section {
        switch self {
        case .conflict, .ciFailing, .changesRequested, .approvalDismissed, .readyToMerge,
             .reviewRequested, .reReview:
            .needsMe
        case .draft, .autoMerge, .ciPending, .moreApprovalsNeeded, .awaitingReview:
            .waiting
        case .inFlight:
            .inFlight
        case .merged, .closed:
            .done
        }
    }
}

extension PullRequest {
    /// Asked to review it, or to look again: the Dashboard's and menu bar's review requests.
    public var needsMyReview: Bool {
        switch attention() {
        case .reviewRequested, .reReview: true
        default: false
        }
    }

    public func attention(now: Date = .now, calendar: Calendar = .current) -> PRAttention {
        switch state {
        case .merged: return .merged
        case .closed: return .closed
        case .open: return isMine ? myAttention(now: now, calendar: calendar) : othersAttention(now: now, calendar: calendar)
        }
    }

    private func myAttention(now: Date, calendar: Calendar) -> PRAttention {
        if isDraft { return .draft }
        if hasConflicts { return .conflict }
        if ciStatus == .failing { return .ciFailing }
        if reviewStatus == .changesRequested { return .changesRequested }
        // With no review rules GitHub gives no decision, so an approval of the head is enough.
        let isApproved = reviewDecision == .approved || (reviewDecision == nil && reviewStatus == .approved)
        if !isApproved && reviewStatus == .approvalDismissed { return .approvalDismissed }
        if isApproved {
            if isAutoMergeEnabled { return .autoMerge }
            if ciStatus == .pending { return .ciPending }
            return .readyToMerge
        }
        if reviewStatus == .approved { return .moreApprovalsNeeded }
        return .awaitingReview(isStale: isStaleForReview(now: now, calendar: calendar))
    }

    private func othersAttention(now: Date, calendar: Calendar) -> PRAttention {
        if isDraft { return .inFlight(isStale: false) }
        if isReviewRequestedFromMe { return myReviewedAt == nil ? .reviewRequested : .reReview }
        if myReviewIsOutdated { return .reReview }
        return .inFlight(isStale: isStaleForReview(now: now, calendar: calendar))
    }

    /// No review since it asked for one, and that was more than `staleAfterWorkingDays` working
    /// days ago.
    private func isStaleForReview(now: Date, calendar: Calendar) -> Bool {
        let since = reviewRequestedAt ?? createdAt
        if let lastReviewedAt, lastReviewedAt > since { return false }
        return now >= addingWorkingDays(PRAttention.staleAfterWorkingDays, to: since, calendar: calendar)
    }
}

/// `days` weekdays after `date`, at the same time of day.
func addingWorkingDays(_ days: Int, to date: Date, calendar: Calendar) -> Date {
    var result = date
    var added = 0
    while added < days {
        result = calendar.date(byAdding: .day, value: 1, to: result)!
        if !calendar.isDateInWeekend(result) { added += 1 }
    }
    return result
}
