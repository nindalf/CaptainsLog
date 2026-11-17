import SwiftUI
import CaptainsLogKit

/// One line per PR, like a todo row: a glyph for where it stands, the title, and in muted text who
/// wrote it, why it's in its section and since when, and its size.
struct PRRow: View {
    let pr: PullRequest
    let attention: PRAttention
    let isSelected: Bool
    /// For a narrow card, as on the Dashboard: one caption after the title, with the author in
    /// place of the reason on someone else's PR, and no size.
    var compact = false

    /// Where the title starts: 8 of padding, 22 of glyph and 10 of gap. A card lines its details
    /// up with it.
    static let titleInset: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            PRGlyph(pr: pr, attention: attention)
                .padding(.leading, 8)
            Text(pr.title)
                .lineLimit(1)
                .foregroundStyle(attention.section == .done ? .secondary : .primary)
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            if compact {
                caption(pr.isMine ? attention.reason(pr) : pr.author?.name)
                    .fixedSize()
                    .padding(.trailing, 8)
            } else {
                Text(pr.isAuthoredByMe ? "you" : pr.author?.name ?? "")
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                caption(attention.reason(pr))
                    .frame(width: 170, alignment: .leading)
                PRSizeBar(additions: pr.additions, deletions: pr.deletions)
                    .frame(width: 48, alignment: .leading)
                    .padding(.trailing, 8)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
        .contentShape(Rectangle())
    }

    /// `label`, then how long ago the reason began.
    private func caption(_ label: String?) -> some View {
        let age = Self.age(since: attention.since(pr))
        return HStack(spacing: 4) {
            Text(label.map { "\($0) · \(age)" } ?? age)
                .lineLimit(1)
            if attention.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
            }
        }
        .font(.caption)
        .foregroundStyle(attention.isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        .help(attention.isStale ? "No review for \(PRAttention.staleAfterWorkingDays) working days" : "")
    }

    /// "40m", "2h", "3d".
    private static func age(since date: Date) -> String {
        let minutes = Int(Date.now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h" }
        return "\(minutes / (24 * 60))d"
    }
}

/// Where a PR stands, as the todo checkbox shows a todo's. Colour only where it needs me.
struct PRGlyph: View {
    let pr: PullRequest
    let attention: PRAttention

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .light))
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .help(attention.label(pr))
            .accessibilityLabel(attention.label(pr))
    }

    private var symbol: String {
        switch attention {
        case .conflict: "exclamationmark.circle"
        case .ciFailing: "xmark.circle"
        case .changesRequested: "pencil.circle"
        case .approvalDismissed: "arrow.counterclockwise.circle"
        case .readyToMerge, .autoMerge, .moreApprovalsNeeded: "checkmark.circle"
        case .reviewRequested, .reReview: "circle.lefthalf.filled"
        case .ciPending: "hourglass.circle"
        case .draft: "circle.dashed"
        case .awaitingReview: "circle"
        case .inFlight:
            if pr.isDraft { "circle.dashed" }
            else if pr.reviewStatus == .approved { "checkmark.circle" }
            else if pr.reviewStatus == .changesRequested { "pencil.circle" }
            else { "circle" }
        case .merged: "circle.fill"
        case .closed: "xmark.circle"
        }
    }

    private var color: AnyShapeStyle {
        switch attention {
        case .conflict, .changesRequested, .approvalDismissed: AnyShapeStyle(.orange)
        case .ciFailing: AnyShapeStyle(.red)
        case .readyToMerge: AnyShapeStyle(.green)
        case .reviewRequested, .reReview: AnyShapeStyle(.blue)
        case .merged, .closed: AnyShapeStyle(.tertiary)
        default: AnyShapeStyle(.secondary)
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
