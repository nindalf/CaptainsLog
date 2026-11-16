import Foundation

/// Why GitHub sync fetched a PR, which decides its flags.
public enum PRSyncSource: Sendable {
    case mine
    /// Assigned to me, whoever wrote it.
    case assignedToMe
    case reviewRequest
    /// Authored by someone whose PRs are synced.
    case teammate
    /// Reviewed by me, whether or not my review was requested.
    case reviewedByMe
    /// A refetch of a PR already in the store, to refresh its state.
    case recheck
}

extension PullRequest {
    /// A review request stays one after the request goes, and wins over `.teammate` and
    /// `.reviewedByMe` whichever order the fetches run in. A PR the reviewed fetch finds first was
    /// requested from a team, or from me before sync saw it; it's treated as a teammate's.
    public func applySyncSource(_ source: PRSyncSource, isNew: Bool) {
        switch source {
        case .mine:
            isAuthoredByMe = true
            isTeammateOnly = false
        case .assignedToMe:
            isAssignedToMe = true
            isTeammateOnly = false
        case .reviewRequest:
            isAuthoredByMe = false
            isTeammateOnly = false
        case .teammate, .reviewedByMe:
            if isNew {
                isAuthoredByMe = false
                isTeammateOnly = true
            }
        case .recheck:
            break
        }
    }

    /// A PR I'm unassigned from that I neither wrote nor was asked to review becomes a
    /// teammate's, not a review request; the review-request fetch takes it back if it is one.
    public func setAssignedToMe(_ assigned: Bool) {
        if assigned {
            applySyncSource(.assignedToMe, isNew: false)
        } else if isAssignedToMe {
            isAssignedToMe = false
            if !isAuthoredByMe { isTeammateOnly = true }
        }
    }
}
