import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "sync.github")

private var ghPath: String { get throws { try SyncTool.gh.requirePath() } }

private let prFields = [
    "number", "title", "state", "url", "createdAt", "mergedAt",
    "reviewDecision", "additions", "deletions", "author",
    "reviewRequests", "body", "isDraft",
].joined(separator: ",")

/// `reviewDecision` means nothing once a PR is merged or closed, and on a page of them it is
/// slow enough on a large monorepo to time out (a 502 after 10s).
private let myClosedFields = [
    "number", "title", "state", "url", "createdAt", "mergedAt",
    "additions", "deletions", "author", "reviewRequests", "body", "isDraft",
].joined(separator: ",")

private let teammateOpenFields = [
    "number", "title", "state", "url", "createdAt",
    "reviewDecision", "additions", "deletions", "author", "isDraft",
].joined(separator: ",")

private let teammateMergedFields = [
    "number", "title", "state", "url", "createdAt", "mergedAt",
    "additions", "deletions", "author", "isDraft",
].joined(separator: ",")

private let reviewFields = [
    "number", "title", "state", "url", "createdAt",
    "author", "reviewDecision", "isDraft",
].joined(separator: ",")

/// No `reviewDecision`, which times out on merged PRs, and most PRs I've reviewed are merged.
private let myReviewFields = [
    "number", "title", "state", "url", "createdAt", "mergedAt",
    "additions", "deletions", "author", "isDraft", "reviews",
].joined(separator: ",")

/// How far back to look for PRs I've reviewed, by the PR's last update. A month catches up after
/// a gap; on a large monorepo it is around 35 PRs and takes under 3 seconds.
private let myReviewWindowDays = 30

/// How many `gh pr view` lookups to run at once when re-checking stale PRs.
private let reconcileConcurrency = 6

// MARK: - DTOs

private struct GHPullRequest: Decodable, Sendable {
    let number: Int
    let title: String
    let state: String
    let url: String
    let createdAt: String
    let mergedAt: String?
    let reviewDecision: String?
    let additions: Int?
    let deletions: Int?
    let author: GHUser?
    let reviewRequests: [GHReviewRequest]?
    let body: String?
    let isDraft: Bool?
    let reviews: [GHReview]?
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

    public func sync(repos: [String]) async throws {
        guard !repos.isEmpty else {
            logger.info("No repos configured, skipping GitHub sync")
            return
        }
        let teammates = try syncedAuthorHandles()

        // One repo failing doesn't stop the rest; what synced is saved, then the failures are thrown.
        var failures: [String] = []
        let myLogin = await fetchMyLogin()
        if myLogin == nil { failures.append("my reviews: couldn't read my GitHub login") }
        for repo in repos {
            try Task.checkCancellation()
            do {
                try await syncMyPRs(repo: repo)
            } catch {
                logger.error("Failed to sync my PRs from \(repo): \(error)")
                failures.append("\(repo) (my PRs): \(error.localizedDescription)")
            }
            // Open PRs these fetches don't return are re-checked one by one, so skip the re-check
            // when a fetch failed rather than re-check everything it would have returned.
            var stillOpen: Set<Int> = []
            var fetchesSucceeded = true
            do {
                stillOpen = try await syncReviewRequests(repo: repo)
            } catch {
                fetchesSucceeded = false
                logger.error("Failed to sync review requests from \(repo): \(error)")
                failures.append("\(repo) (review requests): \(error.localizedDescription)")
            }
            for handle in teammates {
                try Task.checkCancellation()
                do {
                    stillOpen.formUnion(try await syncTeammatePRs(repo: repo, author: handle))
                } catch {
                    fetchesSucceeded = false
                    logger.error("Failed to sync \(handle)'s PRs from \(repo): \(error)")
                    failures.append("\(repo) (\(handle)'s PRs): \(error.localizedDescription)")
                }
            }
            if let myLogin {
                do {
                    stillOpen.formUnion(try await syncMyReviews(repo: repo, myLogin: myLogin))
                } catch {
                    fetchesSucceeded = false
                    logger.error("Failed to sync my reviews from \(repo): \(error)")
                    failures.append("\(repo) (my reviews): \(error.localizedDescription)")
                }
            }
            guard fetchesSucceeded else { continue }
            do {
                try await reconcileStaleOpenPRs(repo: repo, stillOpen: stillOpen)
            } catch {
                logger.error("Failed to re-check open PRs in \(repo): \(error)")
                failures.append("\(repo) (re-check): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        guard failures.isEmpty else { throw SyncError.partial(failures) }
        logger.info("GitHub sync complete")
    }

    private func syncMyPRs(repo: String) async throws {
        async let openPRs = fetchPRs(repo: repo, author: "@me", state: "open", fields: prFields)
        async let mergedPRs = fetchPRs(repo: repo, author: "@me", state: "merged", fields: myClosedFields)
        async let closedPRs = fetchPRs(repo: repo, author: "@me", state: "closed", fields: myClosedFields)
        let allPRs = try await openPRs + mergedPRs + closedPRs
        logger.debug("Fetched \(allPRs.count) of my PRs from \(repo)")

        for ghPR in allPRs {
            try Task.checkCancellation()
            try upsertPR(ghPR, repo: repo, source: .mine)
        }
    }

    /// Open and merged only: a colleague's abandoned PRs aren't worth the calls. Returns the
    /// numbers GitHub confirmed open.
    private func syncTeammatePRs(repo: String, author: String) async throws -> Set<Int> {
        async let openPRs = fetchPRs(repo: repo, author: author, state: "open", fields: teammateOpenFields)
        async let mergedPRs = fetchPRs(repo: repo, author: author, state: "merged", fields: teammateMergedFields)
        let (open, merged) = try await (openPRs, mergedPRs)
        logger.debug("Fetched \(open.count + merged.count) of \(author)'s PRs from \(repo)")

        for ghPR in open + merged {
            try Task.checkCancellation()
            try upsertPR(ghPR, repo: repo, source: .teammate)
        }
        return Set(open.map(\.number))
    }

    /// PRs I've reviewed, including on team requests, which `syncReviewRequests` leaves out and
    /// which stop matching it once reviewed anyway. Returns the numbers GitHub confirmed open.
    private func syncMyReviews(repo: String, myLogin: String) async throws -> Set<Int> {
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
        return Set(prs.filter { $0.state == "OPEN" }.map(\.number))
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

    private func fetchPRs(repo: String, author: String, state: String, fields: String) async throws -> [GHPullRequest] {
        let result = try await runProcess(
            ghPath,
            arguments: [
                "pr", "list",
                "--repo", repo,
                "--author", author,
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
    /// set trips GitHub's per-query resource limits. Returns the numbers GitHub confirmed open,
    /// so `reconcileStaleOpenPRs` knows which local PRs it does not need to re-check.
    private func syncReviewRequests(repo: String) async throws -> Set<Int> {
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

        return Set(prs.map(\.number))
    }

    /// `user-review-requested:@me` stops matching a PR once the request is gone — merged, closed, or
    /// just reviewed — and a teammate's PR leaves their fetch when they are no longer synced, so
    /// such a PR would stay `.open` locally forever. Re-check those by number: `gh pr view` is a direct node lookup, so it has none of the resource-limit
    /// problems the search does.
    private func reconcileStaleOpenPRs(repo: String, stillOpen: Set<Int>) async throws {
        let openState = PRState.open.rawValue
        let stale = try modelContext.fetch(
            FetchDescriptor<PullRequest>(
                predicate: #Predicate {
                    $0.repo == repo && $0.stateRawValue == openState && !$0.isAuthoredByMe
                }
            )
        ).map(\.number).filter { !stillOpen.contains($0) }

        guard !stale.isEmpty else {
            logger.debug("No stale open review requests in \(repo)")
            return
        }

        logger.info("Re-checking \(stale.count) stale open review requests in \(repo)")

        var fetched: [GHPullRequest] = []
        await withTaskGroup(of: GHPullRequest?.self) { group in
            var pending = stale.makeIterator()
            for _ in 0..<reconcileConcurrency {
                guard let number = pending.next() else { break }
                group.addTask { await Self.fetchPR(repo: repo, number: number) }
            }
            while let result = await group.next() {
                if let result { fetched.append(result) }
                if Task.isCancelled { continue }
                if let number = pending.next() {
                    group.addTask { await Self.fetchPR(repo: repo, number: number) }
                }
            }
        }

        try Task.checkCancellation()
        logger.debug("Re-checked \(fetched.count) of \(stale.count) stale PRs in \(repo)")

        for ghPR in fetched {
            try Task.checkCancellation()
            try upsertPR(ghPR, repo: repo, source: .recheck)
        }
    }

    /// `nonisolated` so the concurrent lookups do not serialise back onto the actor.
    private nonisolated static func fetchPR(repo: String, number: Int) async -> GHPullRequest? {
        do {
            let result = try await runProcess(
                ghPath,
                arguments: [
                    "pr", "view", String(number),
                    "--repo", repo,
                    "--json", prFields,
                ],
                timeout: .seconds(30)
            )
            return try JSONDecoder().decode(GHPullRequest.self, from: result.stdout)
        } catch {
            logger.debug("gh pr view failed for \(repo)#\(number): \(error)")
            return nil
        }
    }

    private func upsertPR(_ ghPR: GHPullRequest, repo: String, source: PRSyncSource, myLogin: String? = nil) throws {
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
            guard let url = URL(string: ghPR.url) else { return }
            guard let state = PRState(ghState: ghPR.state) else { return }
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
        // Nil when the fetch didn't ask for the field, so keep what an earlier fetch found.
        if let additions = ghPR.additions { pr.additions = additions }
        if let deletions = ghPR.deletions { pr.deletions = deletions }
        if let body = ghPR.body { pr.body = body }
        pr.isDraft = ghPR.isDraft ?? false
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

    private func parseISO8601(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
