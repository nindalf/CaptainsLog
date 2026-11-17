import Foundation

public enum EntrySource: String, Codable, Sendable, CaseIterable {
    case slack, manual, linear
}

public enum PRState: String, Codable, Sendable, CaseIterable {
    case open, merged, closed

    public init?(ghState: String) {
        switch ghState {
        case "OPEN": self = .open
        case "MERGED": self = .merged
        case "CLOSED": self = .closed
        default: return nil
        }
    }
}

/// Only `.someday` affects lists: it parks an undated todo in Someday. `.inbox` and `.anytime` both
/// mean not Someday; the Inbox or Anytime follows from whether the todo has a project.
public enum TodoSchedule: String, Codable, Sendable, CaseIterable {
    case inbox, anytime, someday
}

public enum Recommendation: String, Codable, Sendable, CaseIterable {
    case yes, no, strongYes, definitelyNot
}

public enum PRDisplayStatus: String, Sendable {
    case draft, open, changesRequested, approved, closed, merged
}

/// Required checks on a PR's head commit. Without required checks, as on a PR stacked on another
/// branch, the overall rollup. `unknown` until enriched, or with no checks at all.
public enum CIStatus: String, Codable, Sendable, CaseIterable {
    case unknown, pending, passing, failing
}

/// Others' reviews of a PR against its head commit. With several, the first case here wins.
public enum PRReviewStatus: String, Codable, Sendable, CaseIterable {
    /// On the head commit, or GitHub's decision says so though no review shows it.
    case changesRequested
    /// Dismissed, or on an older commit.
    case approvalDismissed
    /// On an older commit: pushed since, so it waits for another look.
    case changesRequestedEarlier
    /// On the head commit.
    case approved
    case unreviewed
}

public enum ReviewDecision: String, Codable, Sendable, CaseIterable {
    case approved, changesRequested, commented, reviewRequired, dismissed

    public init?(ghDecision: String) {
        switch ghDecision {
        case "APPROVED": self = .approved
        case "CHANGES_REQUESTED": self = .changesRequested
        case "COMMENTED": self = .commented
        case "REVIEW_REQUIRED": self = .reviewRequired
        case "DISMISSED": self = .dismissed
        default: return nil
        }
    }
}
