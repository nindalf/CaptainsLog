import Foundation

/// Why GitHub sync fetched a PR, which decides its flags.
public enum PRSyncSource: Sendable {
    case mine
    case reviewRequest
    /// Authored by someone whose PRs are synced.
    case teammate
    /// A refetch of a PR already in the store, to refresh its state.
    case recheck
}

extension PullRequest {
    /// A review request stays one after the request goes, and wins over `.teammate`
    /// whichever order the two fetches run in.
    public func applySyncSource(_ source: PRSyncSource, isNew: Bool) {
        switch source {
        case .mine:
            isAuthoredByMe = true
            isTeammateOnly = false
        case .reviewRequest:
            isAuthoredByMe = false
            isTeammateOnly = false
        case .teammate:
            if isNew {
                isAuthoredByMe = false
                isTeammateOnly = true
            }
        case .recheck:
            break
        }
    }
}
