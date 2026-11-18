import SwiftUI
import CaptainsLogKit

/// Lines added and removed as a bar: its length grows with the log of the total, its green share
/// is the additions. The counts are in the hover.
struct PRSizeBar: View {
    let additions: Int?
    let deletions: Int?

    var body: some View {
        if let additions, let deletions, additions + deletions > 0 {
            let total = Double(additions + deletions)
            // Full width at about 4,000 lines.
            let width = min(48, max(4, 4 * log2(total + 1)))
            HStack(spacing: 0) {
                Rectangle().fill(.green.opacity(0.7))
                    .frame(width: width * Double(additions) / total)
                Rectangle().fill(.red.opacity(0.7))
            }
            .frame(width: width, height: 4)
            .clipShape(Capsule())
            .frame(height: 22)
            .contentShape(Rectangle())
            .help("+\(additions) -\(deletions)")
        }
    }
}

extension PRAttention {
    var isStale: Bool {
        switch self {
        case .awaitingReview(let isStale), .inFlight(let isStale): isStale
        default: false
        }
    }

    /// Why it's in its section. Nil where the section says it all.
    func reason(_ pr: PullRequest) -> String? {
        switch self {
        case .conflict: "merge conflict"
        case .ciFailing: "CI failing"
        case .changesRequested: "changes requested"
        case .approvalDismissed: "approval dismissed"
        case .readyToMerge: "ready to merge"
        case .reviewRequested: "review requested"
        case .reReview: "re-review"
        case .draft: "draft"
        case .autoMerge: "auto-merge on"
        case .ciPending: "approved, CI running"
        case .moreApprovalsNeeded: "needs more approvals"
        case .awaitingReview(let isStale): isStale ? "no review" : "awaiting review"
        case .inFlight(let isStale): isStale ? "no review" : pr.isDraft ? "draft" : nil
        case .merged, .closed: nil
        }
    }

    /// What the glyph means, for its hover and VoiceOver.
    func label(_ pr: PullRequest) -> String {
        if let reason = reason(pr) { return reason }
        switch self {
        case .merged: return "merged"
        case .closed: return "closed"
        default:
            switch pr.reviewStatus {
            case .approved: return "approved"
            case .changesRequested: return "changes requested"
            default: return "open"
            }
        }
    }

    /// When the reason began, as near as the PR says: for my PRs' own problems, its last update.
    func since(_ pr: PullRequest) -> Date {
        switch self {
        case .reviewRequested, .reReview, .awaitingReview, .inFlight: pr.reviewRequestedAt ?? pr.createdAt
        case .merged: pr.mergedAt ?? pr.createdAt
        case .draft: pr.createdAt
        default: pr.updatedAt ?? pr.createdAt
        }
    }
}
