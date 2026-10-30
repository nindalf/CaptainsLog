import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "sync")

@Observable
@MainActor
public final class SyncCoordinator {
    public private(set) var lastGitHubSync: Date?
    public private(set) var lastCalendarSync: Date?
    public private(set) var isSyncing = false
    public private(set) var lastError: String?
    /// Kept apart from `lastError`, which the next successful sync clears; this stays until a backup succeeds.
    public private(set) var backupError: String?
    public private(set) var isBackingUp = false

    private let container: ModelContainer
    private let settings: AppSettings
    private var githubTask: Task<Void, Never>?
    private var calendarTask: Task<Void, Never>?
    private var backupTask: Task<Void, Never>?

    public init(container: ModelContainer, settings: AppSettings) {
        self.container = container
        self.settings = settings
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

    // MARK: - Sync methods

    private func syncGitHub() async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let actor = GitHubSync(modelContainer: container)
            try await actor.sync(repos: settings.repos)
            lastGitHubSync = .now
            SyncHistory.update { $0.recordSuccess(.github) }
            lastError = nil
            logger.info("GitHub sync succeeded")
        } catch is CancellationError {
            logger.debug("GitHub sync cancelled")
        } catch {
            SyncHistory.update { $0.recordFailure(.github, error: error.localizedDescription) }
            lastError = "GitHub: \(error.localizedDescription)"
            logger.error("GitHub sync failed: \(error)")
        }
    }

    private func syncCalendar() async {
        isSyncing = true
        defer { isSyncing = false }

        let days = settings.calendarFetchWeeks * 7
        let lastDetailedSync = computeLastDetailedSync()

        do {
            let actor = CalendarSync(modelContainer: container)
            try await actor.sync(
                calendarAllowlist: settings.calendarAllowlist,
                days: days,
                lastDetailedSync: lastDetailedSync
            )
            lastCalendarSync = .now
            SyncHistory.update { $0.recordSuccess(.calendar) }

            if lastDetailedSync == nil {
                settings.lastFullCalendarSync = .now
                logger.info("Full calendar sync completed")
            }

            lastError = nil
            logger.info("Calendar sync succeeded")
        } catch is CancellationError {
            logger.debug("Calendar sync cancelled")
        } catch {
            SyncHistory.update { $0.recordFailure(.calendar, error: error.localizedDescription) }
            lastError = "Calendar: \(error.localizedDescription)"
            logger.error("Calendar sync failed: \(error)")
        }
    }

    /// Runs on schedule, and from Settings. A second call while one is running does nothing.
    public func backUp() async {
        guard !isBackingUp else { return }
        isBackingUp = true
        defer { isBackingUp = false }
        do {
            _ = try await Backup.run(keep: settings.backupKeep)
            SyncHistory.update { $0.recordSuccess(.backup) }
            backupError = nil
            logger.info("Backup succeeded")
        } catch is CancellationError {
            logger.debug("Backup cancelled")
        } catch {
            SyncHistory.update { $0.recordFailure(.backup, error: error.localizedDescription) }
            backupError = "Backup: \(error.localizedDescription)"
            logger.error("Backup failed: \(error)")
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

    private func computeLastDetailedSync() -> Date? {
        let cal = Calendar.current
        let isMonday = cal.component(.weekday, from: .now) == 2

        if isMonday {
            let todayStart = cal.startOfDay(for: .now)
            let lastFull = settings.lastFullCalendarSync
            if lastFull == nil || lastFull! < todayStart {
                return nil
            }
        }

        return lastCalendarSync
    }
}
