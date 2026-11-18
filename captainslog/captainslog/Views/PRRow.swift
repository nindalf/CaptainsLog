import SwiftUI
import CaptainsLogKit

/// A PR's row everywhere it's listed. Its date defaults to how long ago its reason began.
struct PRRecordRow: View {
    let pr: PullRequest
    var attention: PRAttention?
    var date: RowDate?
    var isSelected = false
    var isPadded = true

    var body: some View {
        let attention = attention ?? pr.attention()
        let date = date ?? .age(attention.since(pr))
        RecordRow(isSelected: isSelected, isPadded: isPadded) {
            RecordIcon(kind: .pullRequest)
        } title: {
            Text(pr.title)
        } secondary: {
            PRSecondaryLine(pr: pr, attention: attention)
        } trailing: {
            Text(date.text)
            PRSizeBar(additions: pr.additions, deletions: pr.deletions)
        }
    }
}

/// Who wrote it, its number, and what it needs or where it stands, coloured only when it needs me.
struct PRSecondaryLine: View {
    let pr: PullRequest
    let attention: PRAttention

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: joinedLine(pr.isAuthoredByMe ? "you" : pr.author?.name, "#\(pr.number)") ?? "")
            if let status = attention.status(pr) {
                Text(verbatim: " · ")
                HStack(spacing: 3) {
                    Text(status)
                    if attention.isStale {
                        Image(systemName: "exclamationmark.triangle.fill").imageScale(.small)
                    }
                }
                .foregroundStyle(attention.tint ?? AnyShapeStyle(.secondary))
                .help(attention.isStale ? "No review for \(PRAttention.staleAfterWorkingDays) working days" : "")
            }
        }
    }
}

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
            .frame(height: 12)
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

    /// The colour of what a PR needs from me, nil where it needs nothing.
    var tint: AnyShapeStyle? {
        switch self {
        case .conflict, .changesRequested, .approvalDismissed: AnyShapeStyle(.orange)
        case .ciFailing: AnyShapeStyle(.red)
        case .readyToMerge: AnyShapeStyle(.green)
        case .reviewRequested, .reReview: AnyShapeStyle(.blue)
        default: isStale ? AnyShapeStyle(.orange) : nil
        }
    }

    /// What it needs from me or why it's waiting. Nil when it's neither.
    private func reason(_ pr: PullRequest) -> String? {
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

    /// Why it's in its section, else where it stands. Nil for an open PR with nothing to say.
    func status(_ pr: PullRequest) -> String? {
        if let reason = reason(pr) { return reason }
        switch self {
        case .merged: return "merged"
        case .closed: return "closed"
        default:
            switch pr.reviewStatus {
            case .approved: return "approved"
            case .changesRequested: return "changes requested"
            default: return nil
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
