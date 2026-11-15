import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "sync")

@Observable
@MainActor
public final class SyncCoordinator {
    public private(set) var lastGitHubSync: Date?
    public private(set) var isSyncing = false
    public private(set) var isBackingUp = false
    /// Nil until the first check. Rechecked by `refreshSetup` and before each sync.
    public private(set) var githubSetup: SourceSetup?
    /// Nil until a check succeeds. A failed check keeps the last state rather than reading as logged out.
    public private(set) var calendarSetup: SourceSetup?
    public private(set) var backupStage: Backup.Stage?
    /// Each source's last success and failure, reloaded after every sync and by `refreshSetup`.
    public private(set) var history = SyncHistory.load()
    public private(set) var calendarLogin = CalendarLoginState.idle

    private let container: ModelContainer
    private let settings: AppSettings
    private let googleClient: GoogleClient?
    private var loginTask: Task<Void, Never>?
    private var githubTask: Task<Void, Never>?
    private var calendarTask: Task<Void, Never>?
    private var backupTask: Task<Void, Never>?

    public init(container: ModelContainer, settings: AppSettings, googleClient: GoogleClient? = nil) {
        self.container = container
        self.settings = settings
        self.googleClient = googleClient
    }

    public func startPeriodicSync() {
        guard githubTask == nil else { return }

        githubTask = Task {
            while !Task.isCancelled {
                await syncGitHub()
                do {
                    try await Task.sleep(for: .seconds(settings.githubSyncInterval))
                } catch {
                    break
                }
            }
        }

        calendarTask = Task {
            while !Task.isCancelled {
                await syncCalendar()
                do {
                    try await Task.sleep(for: .seconds(settings.calendarSyncInterval))
                } catch {
                    break
                }
            }
        }

        backupTask = Task {
            while !Task.isCancelled {
                await pruneHistory()
                if Backup.isDue(SyncHistory.load().sources[.backup], interval: settings.backupInterval) {
                    await backUp()
                }
                await pruneExpired()
                do {
                    try await Task.sleep(for: .seconds(60 * 60))
                } catch {
                    break
                }
            }
        }

        logger.info("Started periodic sync")
    }

    public func syncNow() {
        Task {
            await syncGitHub()
            await syncCalendar()
        }
    }

    public func syncCalendarNow() {
        Task {
            await syncCalendar()
        }
    }

    public func syncGitHubNow() {
        Task {
            await syncGitHub()
        }
    }

    // MARK: - Setup

    /// Rechecks every source's setup. The app calls it when it comes to the front, so a step finished
    /// in the terminal shows at once, and a source that has just become ready syncs straight away.
    public func refreshSetup() async {
        let wasGitHub = githubSetup
        let wasCalendar = calendarSetup
        async let github = SetupCheck.github(repos: settings.repos)
        if let calendar = SetupCheck.calendar() { calendarSetup = calendar }
        githubSetup = await github
        backupStage = Backup.status().stage
        history = SyncHistory.load()
        guard !Store.isScratch else { return }
        if githubSetup == .ready, let wasGitHub, wasGitHub != .ready { syncGitHubNow() }
        if calendarSetup == .ready, let wasCalendar, wasCalendar != .ready { syncCalendarNow() }
    }

    /// The repos to sync changed: recheck, and sync so a new repo's PRs show at once.
    public func reposChanged() async {
        githubSetup = await SetupCheck.github(repos: settings.repos)
        if githubSetup == .ready, !Store.isScratch { syncGitHubNow() }
    }

    // MARK: - Calendar login

    /// Only a build that carries the OAuth client can log in.
    public var canLogInToCalendar: Bool { googleClient != nil }

    /// Waits for the user to finish in the browser, then rechecks, which syncs once the login is ready.
    public func startCalendarLogin() {
        guard let googleClient, loginTask == nil else { return }
        calendarLogin = .starting
        loginTask = Task {
            defer { loginTask = nil }
            do {
                try await GoogleLogin.run(client: googleClient, timeout: .seconds(15 * 60)) { url in
                    Task { @MainActor in
                        if self.calendarLogin == .starting { self.calendarLogin = .waiting(url) }
                    }
                }
                calendarLogin = .idle
            } catch is CancellationError {
                calendarLogin = .idle
            } catch {
                calendarLogin = .failed(error.localizedDescription)
            }
            refreshCalendarSetup()
        }
    }

    /// Closes the port Google would redirect to.
    public func cancelCalendarLogin() {
        loginTask?.cancel()
    }

    private func checkCalendarSetup() {
        if let setup = SetupCheck.calendar() { calendarSetup = setup }
    }

    private func refreshCalendarSetup() {
        let was = calendarSetup
        checkCalendarSetup()
        if calendarSetup == .ready, was != .ready, !Store.isScratch { syncCalendarNow() }
    }

    // MARK: - Sync methods

    /// A source that isn't set up skips its sync rather than failing it: its tab says what to do instead.
    private func syncGitHub() async {
        githubSetup = await SetupCheck.github(repos: settings.repos)
        guard githubSetup == .ready else { return }
        isSyncing = true
        defer {
            isSyncing = false
            history = SyncHistory.load()
        }

        do {
            let actor = GitHubSync(modelContainer: container)
            try await actor.sync(repos: settings.repos, skipUpdatedBefore: settings.retention.pullRequests.cutoff())
            lastGitHubSync = .now
            SyncHistory.update { $0.recordSuccess(.github) }
            logger.info("GitHub sync succeeded")
        } catch is CancellationError {
            logger.debug("GitHub sync cancelled")
        } catch {
            SyncHistory.update { $0.recordFailure(.github, error: error.localizedDescription) }
            logger.error("GitHub sync failed: \(error)")
        }
    }

    /// After a failed check, syncs if the calendar was last seen ready, so a broken Keychain shows as a sync error.
    private func syncCalendar() async {
        checkCalendarSetup()
        guard calendarSetup == .ready else { return }
        isSyncing = true
        defer {
            isSyncing = false
            history = SyncHistory.load()
        }

        do {
            let actor = CalendarSync(modelContainer: container)
            try await actor.sync(
                calendarAllowlist: settings.calendarAllowlist,
                weeksAhead: settings.calendarFetchWeeks
            )
            SyncHistory.update { $0.recordSuccess(.calendar) }
            logger.info("Calendar sync succeeded")
        } catch is CancellationError {
            logger.debug("Calendar sync cancelled")
        } catch GoogleAuthError.loggedOut {
            // Google revoked the login, which is gone now: the tab asks to log in again.
            checkCalendarSetup()
        } catch {
            SyncHistory.update { $0.recordFailure(.calendar, error: error.localizedDescription) }
            logger.error("Calendar sync failed: \(error)")
        }
    }

    /// Runs on schedule, and from Settings. A second call while one is running does nothing.
    public func backUp() async {
        guard !isBackingUp else { return }
        isBackingUp = true
        defer {
            isBackingUp = false
            backupStage = Backup.status().stage
            history = SyncHistory.load()
        }
        do {
            _ = try await Backup.run(keep: settings.backupKeep)
            SyncHistory.update { $0.recordSuccess(.backup) }
            logger.info("Backup succeeded")
        } catch is CancellationError {
            logger.debug("Backup cancelled")
        } catch {
            SyncHistory.update { $0.recordFailure(.backup, error: error.localizedDescription) }
            logger.error("Backup failed: \(error)")
        }
    }

    /// Removes records past the retention set in Settings. Every rule is on by default.
    private func pruneExpired() async {
        let retention = settings.retention
        guard retention.isAnyEnabled else { return }
        do {
            let counts = try await RetentionPruner(modelContainer: container).prune(retention)
            logger.info("Retention: cleared \(counts.interviews) interviews, deleted \(counts.calendarEvents) events and \(counts.pullRequests) PRs")
        } catch {
            logger.error("Retention pruning failed: \(error)")
        }
    }

    private func pruneHistory() async {
        do {
            if try await HistoryPruner(modelContainer: container).prune() {
                logger.info("Pruned persistent history")
            }
        } catch {
            logger.error("History pruning failed: \(error)")
        }
    }
}
