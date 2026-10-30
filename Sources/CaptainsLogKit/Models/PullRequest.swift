import Foundation
import SwiftData

@Model
public final class PullRequest {
    public var id: UUID = UUID()
    public var number: Int
    public var title: String
    public var body: String?
    public var url: URL
    public var repo: String
    public var stateRawValue: String = PRState.open.rawValue
    public var state: PRState {
        get { PRState(rawValue: stateRawValue) ?? .open }
        set { stateRawValue = newValue.rawValue }
    }
    public var author: Person?
    public var reviewers: [Person] = []
    public var reviewDecision: ReviewDecision?
    public var createdAt: Date
    public var mergedAt: Date?
    public var additions: Int?
    public var deletions: Int?
    public var isAuthoredByMe: Bool
    /// Synced without my review ever being requested from me personally: its author's PRs are
    /// synced, or I reviewed it on a team request. Stored this way round so the PRs synced before
    /// it existed, all review requests, default right.
    public var isTeammateOnly: Bool = false
    /// When I last submitted a review of it, whoever the review was requested from.
    public var myReviewedAt: Date?
    public var project: Project?
    public var tags: [String] = []
    public var isDraft: Bool = false
    public var deploymentStatus: DeploymentStatus = DeploymentStatus.notDeployed
    public var notes: String?

    /// Came to me as a review request, whether or not it is still open.
    public var isReviewRequest: Bool { !isAuthoredByMe && !isTeammateOnly }

    public var displayStatus: PRDisplayStatus {
        switch state {
        case .merged:
            switch deploymentStatus {
            case .notDeployed: return .merged
            case .partiallyDeployed: return .staging
            case .deployed: return .prod
            }
        case .closed:
            return .closed
        case .open:
            if isDraft { return .draft }
            switch reviewDecision {
            case .approved: return .approved
            case .changesRequested: return .changesRequested
            default: return .open
            }
        }
    }

    #Unique<PullRequest>([\.repo, \.number])
    #Index<PullRequest>([\.stateRawValue])

    public init(
        number: Int,
        title: String,
        url: URL,
        repo: String,
        state: PRState,
        createdAt: Date,
        isAuthoredByMe: Bool
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.repo = repo
        self.stateRawValue = state.rawValue
        self.createdAt = createdAt
        self.isAuthoredByMe = isAuthoredByMe
    }
}
