import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "sync.github")

private var ghPath: String { get throws { try SyncTool.gh.requirePath() } }

private let prFields = [
    "number", "title", "state", "url", "createdAt", "updatedAt", "mergedAt",
    "reviewDecision", "additions", "deletions", "author",
    "reviewRequests", "body", "isDraft", "assignees",
].joined(separator: ",")

/// `reviewDecision` means nothing once a PR is merged or closed, and on a page of them it is
/// slow enough on a large monorepo to time out (a 502 after 10s).
private let myClosedFields = [
    "number", "title", "state", "url", "createdAt", "updatedAt", "mergedAt",
    "additions", "deletions", "author", "reviewRequests", "body", "isDraft",
].joined(separator: ",")

private let teammateOpenFields = [
    "number", "title", "state", "url", "createdAt", "updatedAt",
    "reviewDecision", "additions", "deletions", "author", "isDraft",
].joined(separator: ",")

private let teammateMergedFields = [
    "number", "title", "state", "url", "createdAt", "updatedAt", "mergedAt",
    "additions", "deletions", "author", "isDraft",
].joined(separator: ",")

private let reviewFields = [
    "number", "title", "state", "url", "createdAt", "updatedAt",
    "author", "reviewDecision", "isDraft",
].joined(separator: ",")

/// No `reviewDecision`, which times out on merged PRs, and most PRs I've reviewed are merged.
private let myReviewFields = [
    "number", "title", "state", "url", "createdAt", "updatedAt", "mergedAt",
    "additions", "deletions", "author", "isDraft", "reviews",
].joined(separator: ",")

/// How far back to look for PRs I've reviewed, by the PR's last update. A month catches up after
/// a gap; on a large monorepo it is around 35 PRs and takes under 3 seconds.
private let myReviewWindowDays = 30

// MARK: - DTOs

private struct GHPullRequest: Decodable, Sendable {
    let number: Int
    let title: String
    let state: String
    let url: String
    let createdAt: String
    let updatedAt: String?
    let mergedAt: String?
    let reviewDecision: String?
    let additions: Int?
    let deletions: Int?
    let author: GHUser?
    let reviewRequests: [GHReviewRequest]?
    let body: String?
    let isDraft: Bool?
    let reviews: [GHReview]?
    let assignees: [GHUser]?
}

private struct GHReview: Decodable, Sendable {
    let author: GHUser?
    let submittedAt: String?
}

private struct GHUser: Decodable, Sendable {
    let login: String
}

private struct GHReviewRequest: Decodable, Sendable {
    let login: String?
}

// MARK: - Sync Actor

@ModelActor
public actor GitHubSync {
    /// PRs last updated before this are skipped, so retention's deletes don't come back.
    private var skipUpdatedBefore: Date?

    /// `skipUpdatedBefore` is the PR retention cutoff, nil while that rule is off.
    public func sync(repos: [String], skipUpdatedBefore: Date? = nil) async throws {
        guard !repos.isEmpty else {
            logger.info("No repos configured, skipping GitHub sync")
            return
        }
        self.skipUpdatedBefore = skipUpdatedBefore
        let teammates = try syncedAuthorHandles()

        // One repo failing doesn't stop the rest; what synced is saved, then the failures are thrown.
        var failures: [String] = []
        let myLogin = await fetchMyLogin()
        if myLogin == nil { failures.append("my reviews: couldn't read my GitHub login") }
        for repo in repos {
            try Task.checkCancellation()
            do {
                try await syncMyPRs(repo: repo, myLogin: myLogin)
            } catch {
                logger.error("Failed to sync my PRs from \(repo): \(error)")
                failures.append("\(repo) (my PRs): \(error.localizedDescription)")
            }
            do {
                try await syncReviewRequests(repo: repo)
            } catch {
                logger.error("Failed to sync review requests from \(repo): \(error)")
                failures.append("\(repo) (review requests): \(error.localizedDescription)")
            }
            for handle in teammates {
                try Task.checkCancellation()
                do {
                    try await syncTeammatePRs(repo: repo, author: handle)
                } catch {
                    logger.error("Failed to sync \(handle)'s PRs from \(repo): \(error)")
                    failures.append("\(repo) (\(handle)'s PRs): \(error.localizedDescription)")
                }
            }
            if let myLogin {
                do {
                    try await syncMyReviews(repo: repo, myLogin: myLogin)
                } catch {
                    logger.error("Failed to sync my reviews from \(repo): \(error)")
                    failures.append("\(repo) (my reviews): \(error.localizedDescription)")
                }
            }
            do {
                try await enrichOpenPRs(repo: repo, myLogin: myLogin)
            } catch {
                logger.error("Failed to enrich open PRs in \(repo): \(error)")
                failures.append("\(repo) (open PR details): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        guard failures.isEmpty else { throw SyncError.partial(failures) }
        logger.info("GitHub sync complete")
    }

    /// PRs I authored or am assigned to, such as an agent's opened on my behalf.
    private func syncMyPRs(repo: String, myLogin: String?) async throws {
        async let openPRs = fetchPRs(repo: repo, author: "@me", state: "open", fields: prFields)
        async let mergedPRs = fetchPRs(repo: repo, author: "@me", state: "merged", fields: myClosedFields)
        async let closedPRs = fetchPRs(repo: repo, author: "@me", state: "closed", fields: myClosedFields)
        async let assignedOpenPRs = fetchPRs(repo: repo, assignee: "@me", state: "open", fields: prFields)
        async let assignedMergedPRs = fetchPRs(repo: repo, assignee: "@me", state: "merged", fields: myClosedFields)
        async let assignedClosedPRs = fetchPRs(repo: repo, assignee: "@me", state: "closed", fields: myClosedFields)
        let authored = try await openPRs + mergedPRs + closedPRs
        let assigned = try await assignedOpenPRs + assignedMergedPRs + assignedClosedPRs
        logger.debug("Fetched \(authored.count) authored and \(assigned.count) assigned PRs from \(repo)")

        for ghPR in authored {
            try Task.checkCancellation()
            try upsertPR(ghPR, repo: repo, source: .mine, myLogin: myLogin)
        }
        for ghPR in assigned {
            try Task.checkCancellation()
            try upsertPR(ghPR, repo: repo, source: .assignedToMe, myLogin: myLogin)
        }
    }

    /// Open and merged only: a colleague's abandoned PRs aren't worth the calls.
    private func syncTeammatePRs(repo: String, author: String) async throws {
        async let openPRs = fetchPRs(repo: repo, author: author, state: "open", fields: teammateOpenFields)
        async let mergedPRs = fetchPRs(repo: repo, author: author, state: "merged", fields: teammateMergedFields)
        let (open, merged) = try await (openPRs, mergedPRs)
        logger.debug("Fetched \(open.count + merged.count) of \(author)'s PRs from \(repo)")

        for ghPR in open + merged {
            try Task.checkCancellation()
            try upsertPR(ghPR, repo: repo, source: .teammate)
        }
    }

    /// PRs I've reviewed, including on team requests, which `syncReviewRequests` leaves out and
    /// which stop matching it once reviewed anyway.
    private func syncMyReviews(repo: String, myLogin: String) async throws {
        let since = Calendar.current.date(byAdding: .day, value: -myReviewWindowDays, to: .now)!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let result = try await runProcess(
            ghPath,
            arguments: [
                "pr", "list",
                "--repo", repo,
                "--search", "reviewed-by:@me -author:@me updated:>=\(formatter.string(from: since))",
                "--state", "all",
                "--limit", "50",
                "--json", myReviewFields,
            ],
            timeout: .seconds(60)
        )

        let prs = try JSONDecoder().decode([GHPullRequest].self, from: result.stdout)
        logger.debug("Fetched \(prs.count) PRs I reviewed from \(repo)")

        for ghPR in prs {
            try Task.checkCancellation()
            try upsertPR(ghPR, repo: repo, source: .reviewedByMe, myLogin: myLogin)
        }
    }

    /// Picks my reviews out of a PR's. Nil on failure, which skips only the reviews fetch.
    private func fetchMyLogin() async -> String? {
        do {
            let result = try await runProcess(ghPath, arguments: ["api", "user", "--jq", ".login"], timeout: .seconds(30))
            let login = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return login.isEmpty ? nil : login
        } catch {
            logger.error("Failed to read my GitHub login: \(error)")
            return nil
        }
    }

    private func fetchPRs(
        repo: String, author: String? = nil, assignee: String? = nil, state: String, fields: String
    ) async throws -> [GHPullRequest] {
        let filter = if let author { ["--author", author] } else if let assignee { ["--assignee", assignee] } else { [String]() }
        let result = try await runProcess(
            ghPath,
            arguments: [
                "pr", "list",
                "--repo", repo,
            ] + filter + [
                "--state", state,
                "--limit", "50",
                "--json", fields,
            ],
            timeout: .seconds(60)
        )
        return try JSONDecoder().decode([GHPullRequest].self, from: result.stdout)
    }

    private func syncedAuthorHandles() throws -> [String] {
        let people = try modelContext.fetch(
            FetchDescriptor<Person>(predicate: #Predicate { $0.syncsPullRequests && $0.githubHandle != nil })
        )
        return Array(Set(people.compactMap(\.githubHandle))).sorted()
    }

    /// Discovers review requests made to me, not to my teams: `review-requested:@me` also matches
    /// team requests, around 70 open on a large monorepo, mostly from people I don't work with.
    /// Teammates' PRs come through `syncTeammatePRs` instead.
    /// Only `--state open` is queried: `user-review-requested:@me` is a GraphQL search, and on a large monorepo anything beyond a small result
    /// set trips GitHub's per-query resource limits.
    private func syncReviewRequests(repo: String) async throws {
        let result = try await runProcess(
            ghPath,
            arguments: [
                "pr", "list",
                "--repo", repo,
                "--search", "user-review-requested:@me",
                "--state", "open",
                "--limit", "50",
                "--json", reviewFields,
            ],
            timeout: .seconds(60)
        )

        let prs = try JSONDecoder().decode([GHPullRequest].self, from: result.stdout)
        logger.debug("Fetched \(prs.count) open review requests from \(repo)")

        for ghPR in prs {
            try Task.checkCancellation()
            try upsertPR(ghPR, repo: repo, source: .reviewRequest)
        }
    }

    /// Every PR open locally, looked up by number for its CI, mergeability, reviews and review
    /// requests. This also catches a PR the fetches above no longer return, which would otherwise
    /// stay open locally for good: a review request once merged, closed or reviewed, a teammate's
    /// once they are no longer synced, or one I'm unassigned from. A failed batch doesn't stop
    /// the rest; the failures are thrown once what came back is applied.
    private func enrichOpenPRs(repo: String, myLogin: String?) async throws {
        let openState = PRState.open.rawValue
        let numbers = try modelContext.fetch(
            FetchDescriptor<PullRequest>(
                predicate: #Predicate { $0.repo == repo && $0.stateRawValue == openState }
            )
        ).map(\.number).sorted()
        guard !numbers.isEmpty else { return }

        var fetched: [GQLPullRequest] = []
        var failures: [String] = []
        for start in stride(from: 0, to: numbers.count, by: enrichmentBatchSize) {
            try Task.checkCancellation()
            let batch = Array(numbers[start..<min(start + enrichmentBatchSize, numbers.count)])
            do {
                let result = try await fetchDetails(repo: repo, query: enrichmentQuery(numbers: batch))
                fetched += result.prs.values
                failures += result.errors
            } catch {
                logger.error("Failed to enrich PRs \(batch) in \(repo): \(error)")
                failures.append(error.localizedDescription)
            }
        }
        logger.debug("Enriched \(fetched.count) of \(numbers.count) open PRs in \(repo)")

        var requiredByBase: [String: Set<String>] = [:]
        for base in Set(fetched.compactMap(\.baseRefName)) {
            requiredByBase[base] = await fetchRequiredChecks(repo: repo, branch: base)
        }

        for details in fetched {
            try Task.checkCancellation()
            guard let ghPR = details.listPR,
                  let pr = try upsertPR(ghPR, repo: repo, source: .recheck, myLogin: myLogin) else { continue }
            if let checks = await allChecks(of: details, repo: repo, number: ghPR.number) {
                // Some required checks only start once a PR leaves draft, so a draft goes by the
                // ones that have started.
                let required = details.isDraft == true ? [] : details.baseRefName.flatMap { requiredByBase[$0] } ?? []
                pr.ciStatus = CIRollup.evaluate(checks: checks, required: required, rollupState: details.rollup?.state)
            }
            switch details.mergeable {
            case "CONFLICTING": pr.hasConflicts = true
            case "MERGEABLE": pr.hasConflicts = false
            default: break
            }
            pr.isAutoMergeEnabled = details.autoMergeRequest != nil
            let reviews = summarizeReviews(
                mergeReviews(latest: details.latestReviews?.items ?? [], opinionated: details.latestOpinionatedReviews?.items ?? []),
                head: details.headRefOid, author: details.author?.login, myLogin: myLogin,
                isMine: pr.isMine, decision: details.reviewDecision
            )
            pr.reviewStatus = reviews.status
            pr.myReviewIsOutdated = reviews.myReviewIsOutdated
            pr.lastReviewedAt = reviews.lastReviewedAt
            if let myLogin {
                pr.isReviewRequestedFromMe = (details.reviewRequests?.items ?? []).contains {
                    $0.requestedReviewer?.login?.caseInsensitiveCompare(myLogin) == .orderedSame
                }
            }
            pr.reviewRequestedAt = details.timelineItems?.items.last?.createdAt.flatMap(parseISO8601)
        }
        // A failed batch often gives every PR in it the same error.
        let distinct = failures.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        guard distinct.isEmpty else { throw SyncError.partial(distinct) }
    }

    private func fetchDetails(repo: String, query: String, variables: [String: String] = [:]) async throws -> EnrichmentResult {
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return EnrichmentResult(prs: [:], errors: ["not a repo: \(repo)"]) }
        let fields = (["owner": parts[0], "name": parts[1], "query": query].merging(variables) { a, _ in a })
            .flatMap { ["-f", "\($0.key)=\($0.value)"] }
        let result = try await runProcess(
            ghPath, arguments: ["api", "graphql"] + fields, timeout: .seconds(60), allowsNonZeroExit: true
        )
        return try decodeEnrichment(stdout: result.stdout, exitCode: result.exitCode, stderr: result.stderrString)
    }

    /// The first page of checks and any more. Nil when a further page fails, which leaves the
    /// PR's CI as it was.
    private func allChecks(of details: GQLPullRequest, repo: String, number: Int) async -> [CICheck]? {
        var checks = details.rollup?.contexts.nodes.compactMap { $0?.check } ?? []
        var pageInfo = details.rollup?.contexts.pageInfo
        for _ in 0..<maxExtraCheckPages {
            guard let info = pageInfo, info.hasNextPage, let cursor = info.endCursor else { break }
            do {
                let page = try await fetchDetails(repo: repo, query: checksPageQuery(number: number), variables: ["after": cursor])
                guard let contexts = page.prs.values.first?.rollup?.contexts else { break }
                checks += contexts.nodes.compactMap { $0?.check }
                pageInfo = contexts.pageInfo
            } catch {
                logger.error("Failed to fetch more checks for \(repo)#\(number): \(error)")
                return nil
            }
        }
        return checks
    }

    /// Empty when the rules can't be read: GitHub's `isRequired` still marks the checks that have
    /// started.
    private func fetchRequiredChecks(repo: String, branch: String) async -> Set<String> {
        let encoded = branch.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? branch
        do {
            let result = try await runProcess(
                ghPath, arguments: ["api", "repos/\(repo)/rules/branches/\(encoded)?per_page=100"], timeout: .seconds(30)
            )
            return try decodeRequiredChecks(result.stdout)
        } catch {
            logger.error("Failed to read the rules for \(repo) \(branch): \(error)")
            return []
        }
    }

    /// Nil when skipped: past the retention cutoff, or a new PR missing what it needs.
    @discardableResult
    private func upsertPR(_ ghPR: GHPullRequest, repo: String, source: PRSyncSource, myLogin: String? = nil) throws -> PullRequest? {
        let updatedAt = ghPR.updatedAt.flatMap(parseISO8601)
        if let skipUpdatedBefore, let updatedAt, updatedAt < skipUpdatedBefore { return nil }
        let number = ghPR.number
        let existing = try modelContext.fetch(
            FetchDescriptor<PullRequest>(
                predicate: #Predicate { $0.repo == repo && $0.number == number }
            )
        ).first

        let pr: PullRequest
        if let existing {
            pr = existing
        } else {
            guard let url = URL(string: ghPR.url) else { return nil }
            guard let state = PRState(ghState: ghPR.state) else { return nil }
            pr = PullRequest(
                number: number,
                title: ghPR.title,
                url: url,
                repo: repo,
                state: state,
                createdAt: parseISO8601(ghPR.createdAt) ?? .now,
                isAuthoredByMe: source == .mine
            )
            modelContext.insert(pr)
        }
        pr.applySyncSource(source, isNew: existing == nil)

        pr.title = ghPR.title
        if let state = PRState(ghState: ghPR.state) {
            pr.state = state
        }
        if let decision = ghPR.reviewDecision, !decision.isEmpty {
            pr.reviewDecision = ReviewDecision(ghDecision: decision)
        }
        if let mergedAt = ghPR.mergedAt {
            pr.mergedAt = parseISO8601(mergedAt)
        }
        if let updatedAt { pr.updatedAt = updatedAt }
        // Nil when the fetch didn't ask for the field, so keep what an earlier fetch found.
        if let additions = ghPR.additions { pr.additions = additions }
        if let deletions = ghPR.deletions { pr.deletions = deletions }
        if let body = ghPR.body { pr.body = body }
        pr.isDraft = ghPR.isDraft ?? false
        // Only fetches that ask for `assignees` can see an unassignment: my open PRs and enrichment.
        if let myLogin, let assignees = ghPR.assignees {
            pr.setAssignedToMe(assignees.contains { $0.login.caseInsensitiveCompare(myLogin) == .orderedSame })
        }
        if let myLogin, let reviews = ghPR.reviews {
            let mine = reviews.filter { $0.author?.login.caseInsensitiveCompare(myLogin) == .orderedSame }
            if let latest = mine.compactMap({ $0.submittedAt.flatMap(parseISO8601) }).max() {
                pr.myReviewedAt = latest
            }
        }

        if let authorLogin = ghPR.author?.login {
            pr.author = try findOrCreatePerson(githubHandle: authorLogin)
        }

        if let requests = ghPR.reviewRequests {
            let reviewerLogins = requests.compactMap(\.login)
            if !reviewerLogins.isEmpty {
                pr.reviewers = try reviewerLogins.map { try findOrCreatePerson(githubHandle: $0) }
            }
        }
        return pr
    }

    private func findOrCreatePerson(githubHandle: String) throws -> Person {
        let existing = try modelContext.fetch(
            FetchDescriptor<Person>(
                predicate: #Predicate { $0.githubHandle == githubHandle }
            )
        ).first

        if let existing { return existing }
        // Logins are case-insensitive, and a handle typed into a roster or by hand may not
        // match GitHub's casing. Only reached for a login not seen before.
        let handled = try modelContext.fetch(
            FetchDescriptor<Person>(predicate: #Predicate { $0.githubHandle != nil })
        )
        if let match = handled.first(where: { $0.githubHandle?.caseInsensitiveCompare(githubHandle) == .orderedSame }) {
            return match
        }

        let person = Person(name: githubHandle, githubHandle: githubHandle)
        modelContext.insert(person)
        return person
    }
}

private extension GQLPullRequest {
    /// The fields a list fetch gives, for `upsertPR`. Nil without what a new PR needs.
    var listPR: GHPullRequest? {
        guard let number, let title, let state, let url, let createdAt else { return nil }
        return GHPullRequest(
            number: number, title: title, state: state, url: url, createdAt: createdAt,
            updatedAt: updatedAt, mergedAt: mergedAt, reviewDecision: reviewDecision,
            additions: additions, deletions: deletions, author: author?.login.map(GHUser.init),
            reviewRequests: reviewRequests?.items.map { GHReviewRequest(login: $0.requestedReviewer?.login) },
            body: body, isDraft: isDraft,
            reviews: latestReviews?.items.map { GHReview(author: $0.author.map { GHUser(login: $0.login) }, submittedAt: $0.submittedAt) },
            assignees: assignees?.items.compactMap { $0.login.map(GHUser.init) }
        )
    }
}
