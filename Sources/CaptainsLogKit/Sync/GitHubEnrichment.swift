import Foundation

// The GraphQL lookup that fills in an open PR's CI, mergeability, reviews and review requests.
// `gh pr list` can't ask which checks are required. Aliased `pullRequest(number:)` lookups are
// direct node lookups, so they have none of the search's resource limits, and a batch of them
// costs one rate-limit point.

/// PRs per query. Each brings up to a page of checks; 20 took around 10 seconds, where GitHub
/// cuts a query off.
let enrichmentBatchSize = 10
/// Checks per page. A PR with more fetches the rest by cursor.
let enrichmentCheckPageSize = 100
/// Pages of checks to follow past the first for one PR, so a runaway CI can't loop sync.
let maxExtraCheckPages = 4

func enrichmentQuery(numbers: [Int]) -> String {
    let lookups = numbers.map { number in
        """
        p\(number): pullRequest(number: \(number)) {
          number title state url body createdAt updatedAt mergedAt isDraft reviewDecision
          additions deletions mergeable baseRefName headRefOid
          author { login }
          autoMergeRequest { enabledAt }
          assignees(first: 20) { nodes { login } }
          reviewRequests(first: 50) { nodes { requestedReviewer { ... on User { login } } } }
          latestReviews(first: 100) { nodes { ...review } }
          latestOpinionatedReviews(first: 100) { nodes { ...review } }
          timelineItems(last: 1, itemTypes: [REVIEW_REQUESTED_EVENT, READY_FOR_REVIEW_EVENT]) {
            nodes { ... on ReviewRequestedEvent { createdAt } ... on ReadyForReviewEvent { createdAt } }
          }
          \(checksSelection(number: number, paged: false))
        }
        """
    }
    return """
    query($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
    \(lookups.joined(separator: "\n"))
      }
    }
    fragment review on PullRequestReview { author { __typename login } state submittedAt commit { oid } }
    """
}

/// The next page of one PR's checks, from the `after` variable.
func checksPageQuery(number: Int) -> String {
    """
    query($owner: String!, $name: String!, $after: String!) {
      repository(owner: $owner, name: $name) {
        p\(number): pullRequest(number: \(number)) { \(checksSelection(number: number, paged: true)) }
      }
    }
    """
}

private func checksSelection(number: Int, paged: Bool) -> String {
    """
    commits(last: 1) { nodes { commit { statusCheckRollup { state
      contexts(first: \(enrichmentCheckPageSize)\(paged ? ", after: $after" : "")) {
        pageInfo { hasNextPage endCursor }
        nodes {
          ... on CheckRun { name status conclusion startedAt isRequired(pullRequestNumber: \(number)) }
          ... on StatusContext { context state createdAt isRequired(pullRequestNumber: \(number)) }
        }
      }
    } } } }
    """
}

/// The PRs a query found, by alias, and the errors for those it couldn't look up. A PR GitHub
/// can't find, deleted say, is neither.
struct EnrichmentResult {
    var prs: [String: GQLPullRequest]
    var errors: [String]
}

func decodeEnrichment(stdout: Data, exitCode: Int32, stderr: String) throws -> EnrichmentResult {
    let failed = ProcessError.nonZeroExit(code: exitCode, stderr: stderr)
    let response: GQLResponse
    do {
        response = try JSONDecoder().decode(GQLResponse.self, from: stdout)
    } catch {
        throw exitCode == 0 ? error : failed
    }
    guard let repository = response.data?.repository else {
        let messages = (response.errors ?? []).map(\.message)
        throw exitCode == 0 && !messages.isEmpty ? SyncError.partial(messages) : failed
    }
    let errors = (response.errors ?? []).filter { $0.type != "NOT_FOUND" }.map(\.message)
    return EnrichmentResult(prs: repository.compactMapValues { $0 }, errors: errors)
}

// MARK: - DTOs

struct GQLResponse: Decodable {
    struct DataField: Decodable {
        let repository: [String: GQLPullRequest?]?
    }
    struct GQLError: Decodable {
        let type: String?
        let message: String
    }
    let data: DataField?
    let errors: [GQLError]?
}

struct GQLNodes<T: Decodable & Sendable>: Decodable, Sendable {
    let nodes: [T?]
    var items: [T] { nodes.compactMap { $0 } }
}

struct GQLLogin: Decodable, Sendable {
    let login: String?
}

struct GQLPullRequest: Decodable, Sendable {
    let number: Int?
    let title: String?
    let state: String?
    let url: String?
    let body: String?
    let createdAt: String?
    let updatedAt: String?
    let mergedAt: String?
    let isDraft: Bool?
    let reviewDecision: String?
    let additions: Int?
    let deletions: Int?
    let mergeable: String?
    let baseRefName: String?
    let headRefOid: String?
    let author: GQLLogin?
    let autoMergeRequest: GQLAutoMerge?
    let assignees: GQLNodes<GQLLogin>?
    let reviewRequests: GQLNodes<GQLReviewRequest>?
    let latestReviews: GQLNodes<GQLReview>?
    let latestOpinionatedReviews: GQLNodes<GQLReview>?
    let timelineItems: GQLNodes<GQLTimelineItem>?
    let commits: GQLNodes<GQLCommitNode>

    var rollup: GQLRollup? { commits.items.first?.commit.statusCheckRollup }
}

struct GQLAutoMerge: Decodable, Sendable {
    let enabledAt: String?
}

struct GQLReviewRequest: Decodable, Sendable {
    /// Nil fields for a team.
    let requestedReviewer: GQLLogin?
}

struct GQLReview: Decodable, Sendable {
    struct Author: Decodable, Sendable {
        let __typename: String?
        let login: String
    }
    let author: Author?
    let state: String
    let submittedAt: String?
    let commit: GQLCommitRef?
}

struct GQLCommitRef: Decodable, Sendable {
    let oid: String
}

struct GQLTimelineItem: Decodable, Sendable {
    let createdAt: String?
}

struct GQLCommitNode: Decodable, Sendable {
    struct Commit: Decodable, Sendable {
        let statusCheckRollup: GQLRollup?
    }
    let commit: Commit
}

struct GQLRollup: Decodable, Sendable {
    struct PageInfo: Decodable, Sendable {
        let hasNextPage: Bool
        let endCursor: String?
    }
    struct Contexts: Decodable, Sendable {
        let pageInfo: PageInfo
        let nodes: [GQLCheckContext?]
    }
    let state: String?
    let contexts: Contexts
}

/// A `CheckRun` or a `StatusContext`.
struct GQLCheckContext: Decodable, Sendable {
    let name: String?
    let status: String?
    let conclusion: String?
    let startedAt: String?
    let context: String?
    let state: String?
    let createdAt: String?
    let isRequired: Bool?

    var check: CICheck? {
        if let name {
            let result: CICheck.Result = if status != "COMPLETED" {
                .pending
            } else {
                switch conclusion {
                case "SUCCESS", "NEUTRAL", "SKIPPED": .passed
                default: .failed
                }
            }
            return CICheck(name: name, isRequired: isRequired ?? false, result: result, startedAt: startedAt.flatMap(parseISO8601))
        }
        if let context {
            let result: CICheck.Result = switch state {
            case "SUCCESS": .passed
            case "PENDING", "EXPECTED": .pending
            default: .failed
            }
            return CICheck(name: context, isRequired: isRequired ?? false, result: result, startedAt: createdAt.flatMap(parseISO8601))
        }
        return nil
    }
}

func parseISO8601(_ string: String) -> Date? {
    ISO8601DateFormatter().date(from: string)
}

// MARK: - Reviews

/// A reviewer's latest say, in GitHub's states: APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED.
struct ReviewSnapshot: Equatable {
    var login: String
    var state: String
    var commitOID: String?
    var submittedAt: Date?
}

/// Each person's latest say on a PR. `latestReviews` is their latest review of any kind, so a
/// comment after an approval hides it; `latestOpinionatedReviews` keeps the approval or change
/// request but drops a dismissed one. Behind a comment the opinion stands, timed by the comment
/// so it still counts as reviewing. Bots are left out: an automatic review on every PR would
/// keep any from going stale.
func mergeReviews(latest: [GQLReview], opinionated: [GQLReview]) -> [ReviewSnapshot] {
    let isPerson = { (review: GQLReview) in review.author != nil && review.author?.__typename != "Bot" }
    let opinions = Dictionary(opinionated.filter(isPerson).map { ($0.author!.login, $0) }, uniquingKeysWith: { a, _ in a })
    var reviews: [ReviewSnapshot] = []
    var seen: Set<String> = []
    for review in latest.filter(isPerson) + opinionated.filter(isPerson) {
        let login = review.author!.login
        guard seen.insert(login).inserted else { continue }
        let say = review.state == "COMMENTED" ? opinions[login] ?? review : review
        reviews.append(ReviewSnapshot(
            login: login, state: say.state, commitOID: say.commit?.oid,
            submittedAt: review.submittedAt.flatMap(parseISO8601)
        ))
    }
    return reviews
}

struct ReviewSummary: Equatable {
    var status: PRReviewStatus
    var myReviewIsOutdated: Bool
    var lastReviewedAt: Date?
}

/// What `PullRequest.attention` needs from the reviews. `isMine`: my PR, where my own reviews
/// don't count.
func summarizeReviews(
    _ reviews: [ReviewSnapshot], head: String?, author: String?, myLogin: String?, isMine: Bool, decision: String?
) -> ReviewSummary {
    let matches = { (login: String, other: String?) in other.map { login.caseInsensitiveCompare($0) == .orderedSame } ?? false }
    // Unknown counts as on the head, so a review isn't read as pushed past without evidence.
    let onHead = { (review: ReviewSnapshot) in head == nil || review.commitOID == nil || review.commitOID == head }
    let others = reviews.filter { !matches($0.login, myLogin) && !matches($0.login, author) }
    let changeRequests = others.filter { $0.state == "CHANGES_REQUESTED" }

    let status: PRReviewStatus
    if changeRequests.contains(where: onHead) || (changeRequests.isEmpty && decision == "CHANGES_REQUESTED") {
        status = .changesRequested
    } else if others.contains(where: { $0.state == "DISMISSED" || ($0.state == "APPROVED" && !onHead($0)) }) {
        status = .approvalDismissed
    } else if !changeRequests.isEmpty {
        status = .changesRequestedEarlier
    } else if others.contains(where: { $0.state == "APPROVED" }) {
        status = .approved
    } else {
        status = .unreviewed
    }

    let mine = reviews.first { matches($0.login, myLogin) }
    let counted = reviews.filter { !matches($0.login, author) && !(isMine && matches($0.login, myLogin)) }
    return ReviewSummary(
        status: status,
        myReviewIsOutdated: mine.map { $0.state == "CHANGES_REQUESTED" && !onHead($0) } ?? false,
        lastReviewedAt: counted.compactMap(\.submittedAt).max()
    )
}

// MARK: - CI

/// One check run or commit status on a PR's head commit.
public struct CICheck: Sendable, Equatable {
    public enum Result: Sendable { case pending, passed, failed }

    public var name: String
    public var isRequired: Bool
    public var result: Result
    public var startedAt: Date?

    public init(name: String, isRequired: Bool, result: Result, startedAt: Date? = nil) {
        self.name = name
        self.isRequired = isRequired
        self.result = result
        self.startedAt = startedAt
    }
}

public enum CIRollup {
    /// `required` are the names the base branch's rules require: a required check that hasn't
    /// started yet has no run to say so. Re-runs leave several runs of a name; the latest counts.
    /// Skipped and neutral runs pass, as GitHub treats them. With nothing required, as on a PR
    /// stacked on another branch, it falls back to GitHub's overall `rollupState`.
    public static func evaluate(checks: [CICheck], required: Set<String>, rollupState: String?) -> CIStatus {
        var latest: [String: CICheck] = [:]
        for check in checks {
            if let existing = latest[check.name], let old = existing.startedAt,
               let new = check.startedAt, new < old {
                continue
            }
            latest[check.name] = check
        }
        let isRequired = { (check: CICheck) in check.isRequired || required.contains(check.name) }
        let blocking = latest.values.filter(isRequired)
        guard !blocking.isEmpty || !required.isEmpty else {
            return switch rollupState {
            case "SUCCESS": .passing
            case "FAILURE", "ERROR": .failing
            case "PENDING", "EXPECTED": .pending
            default: .unknown
            }
        }
        if blocking.contains(where: { $0.result == .failed }) { return .failing }
        let notStarted = !required.isSubset(of: Set(latest.keys))
        if notStarted || blocking.contains(where: { $0.result == .pending }) { return .pending }
        return .passing
    }
}

// MARK: - Rules

private struct GHRule: Decodable {
    struct Parameters: Decodable {
        struct Check: Decodable { let context: String }
        let required_status_checks: [Check]?
    }
    let type: String
    let parameters: Parameters?
}

/// The check names a branch's rulesets require. Empty when none do.
func decodeRequiredChecks(_ data: Data) throws -> Set<String> {
    let rules = try JSONDecoder().decode([GHRule].self, from: data)
    return Set(rules.filter { $0.type == "required_status_checks" }
        .flatMap { $0.parameters?.required_status_checks ?? [] }
        .map(\.context))
}
