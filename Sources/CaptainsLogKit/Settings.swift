import Foundation
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "settings")

@Observable
public final class AppSettings: @unchecked Sendable {
    private let defaults: UserDefaults

    /// The app's bundle ID. The app reads it as `.standard`; the CLI opens it as a suite,
    /// since a suite named after the running app's own bundle ID is rejected.
    public static let domain = "com.nindalf.captainslog"

    public init() {
        self.defaults = Bundle.main.bundleIdentifier == Self.domain
            ? .standard
            : UserDefaults(suiteName: Self.domain) ?? .standard
    }

    public var repos: [String] {
        get {
            access(keyPath: \.repos)
            return defaults.stringArray(forKey: "githubRepos") ?? []
        }
        set {
            withMutation(keyPath: \.repos) {
                defaults.set(newValue, forKey: "githubRepos")
            }
            logger.debug("Updated repos: \(newValue)")
        }
    }

    /// GitHub handles whose PRs the app hides. They still sync.
    public var hiddenPRAuthors: [String] {
        get {
            access(keyPath: \.hiddenPRAuthors)
            return defaults.stringArray(forKey: "hiddenPRAuthors") ?? []
        }
        set {
            withMutation(keyPath: \.hiddenPRAuthors) {
                defaults.set(newValue, forKey: "hiddenPRAuthors")
            }
            logger.debug("Updated hidden PR authors: \(newValue)")
        }
    }

    public func isHidden(_ pr: PullRequest) -> Bool {
        guard !pr.isAuthoredByMe, let handle = pr.author?.githubHandle else { return false }
        return hiddenPRAuthors.contains(handle)
    }

    /// Sidebar tabs by raw value, in display order. The app appends tabs missing from it.
    public var sidebarOrder: [String] {
        get {
            access(keyPath: \.sidebarOrder)
            return defaults.stringArray(forKey: "sidebarOrder") ?? []
        }
        set {
            withMutation(keyPath: \.sidebarOrder) {
                defaults.set(newValue, forKey: "sidebarOrder")
            }
            logger.debug("Updated sidebar order: \(newValue)")
        }
    }

    /// Sidebar tabs, by raw value, left out of the sidebar.
    public var hiddenSidebarTabs: [String] {
        get {
            access(keyPath: \.hiddenSidebarTabs)
            return defaults.stringArray(forKey: "hiddenSidebarTabs") ?? []
        }
        set {
            withMutation(keyPath: \.hiddenSidebarTabs) {
                defaults.set(newValue, forKey: "hiddenSidebarTabs")
            }
            logger.debug("Updated hidden sidebar tabs: \(newValue)")
        }
    }

    /// Dashboard setup steps, by id, the user chose to skip.
    public var skippedSetupSteps: [String] {
        get {
            access(keyPath: \.skippedSetupSteps)
            return defaults.stringArray(forKey: "skippedSetupSteps") ?? []
        }
        set {
            withMutation(keyPath: \.skippedSetupSteps) {
                defaults.set(newValue, forKey: "skippedSetupSteps")
            }
            logger.debug("Updated skipped setup steps: \(newValue)")
        }
    }

    public var calendarAllowlist: [String] {
        get {
            access(keyPath: \.calendarAllowlist)
            return defaults.stringArray(forKey: "calendarAllowlist") ?? []
        }
        set {
            withMutation(keyPath: \.calendarAllowlist) {
                defaults.set(newValue, forKey: "calendarAllowlist")
            }
            logger.debug("Updated calendar allowlist: \(newValue)")
        }
    }

    public var githubSyncInterval: TimeInterval {
        get {
            let val = defaults.double(forKey: "githubSyncInterval")
            return val > 0 ? val : 300
        }
        set { defaults.set(newValue, forKey: "githubSyncInterval") }
    }

    public var calendarSyncInterval: TimeInterval {
        get {
            let val = defaults.double(forKey: "calendarSyncInterval")
            return val > 0 ? val : 600
        }
        set { defaults.set(newValue, forKey: "calendarSyncInterval") }
    }

    public var backupInterval: TimeInterval {
        get {
            access(keyPath: \.backupInterval)
            let val = defaults.double(forKey: "backupInterval")
            return val > 0 ? val : 24 * 60 * 60
        }
        set {
            withMutation(keyPath: \.backupInterval) {
                defaults.set(newValue, forKey: "backupInterval")
            }
            logger.debug("Updated backupInterval: \(newValue)")
        }
    }

    public var backupKeep: Int {
        get {
            access(keyPath: \.backupKeep)
            let val = defaults.integer(forKey: "backupKeep")
            return val > 0 ? val : 30
        }
        set {
            withMutation(keyPath: \.backupKeep) {
                defaults.set(newValue, forKey: "backupKeep")
            }
            logger.debug("Updated backupKeep: \(newValue)")
        }
    }

    /// Separate keys per rule, so a sandbox can try one as a launch argument
    /// (`-retentionPullRequestsEnabled YES`), which is never saved.
    public var retention: RetentionSettings {
        get {
            access(keyPath: \.retention)
            let defaultDays = RetentionSettings.defaultDays
            return RetentionSettings(
                interviews: rule("Interviews", defaultDays: defaultDays.interviews),
                calendarEvents: rule("CalendarEvents", defaultDays: defaultDays.calendarEvents),
                pullRequests: rule("PullRequests", defaultDays: defaultDays.pullRequests)
            )
        }
        set {
            withMutation(keyPath: \.retention) {
                setRule(newValue.interviews, "Interviews")
                setRule(newValue.calendarEvents, "CalendarEvents")
                setRule(newValue.pullRequests, "PullRequests")
            }
            logger.debug("Updated retention: \(String(describing: newValue))")
        }
    }

    private func rule(_ kind: String, defaultDays: Int) -> RetentionRule {
        let days = defaults.integer(forKey: "retention\(kind)Days")
        return RetentionRule(
            isEnabled: defaults.bool(forKey: "retention\(kind)Enabled"),
            days: RetentionRule.dayChoices.contains(days) ? days : defaultDays
        )
    }

    private func setRule(_ rule: RetentionRule, _ kind: String) {
        defaults.set(rule.isEnabled, forKey: "retention\(kind)Enabled")
        defaults.set(rule.days, forKey: "retention\(kind)Days")
    }

    /// Control-Space opens the quick entry panel from any app. Off by default.
    public var quickEntryEnabled: Bool {
        get {
            access(keyPath: \.quickEntryEnabled)
            return defaults.object(forKey: "quickEntryEnabled") as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.quickEntryEnabled) {
                defaults.set(newValue, forKey: "quickEntryEnabled")
            }
            logger.debug("Updated quickEntryEnabled: \(newValue)")
        }
    }

    public var showWeekends: Bool {
        get { defaults.object(forKey: "showWeekends") as? Bool ?? false }
        set {
            defaults.set(newValue, forKey: "showWeekends")
            logger.debug("Updated showWeekends: \(newValue)")
        }
    }

    public var calendarFetchWeeks: Int {
        get {
            let val = defaults.integer(forKey: "calendarFetchWeeks")
            return val > 0 ? val : 4
        }
        set {
            defaults.set(newValue, forKey: "calendarFetchWeeks")
            logger.debug("Updated calendarFetchWeeks: \(newValue)")
        }
    }
}
