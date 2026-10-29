import Foundation
import Testing
import CaptainsLogKit

struct SyncHistoryTests {
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 15))!

    private func hours(_ offset: Double) -> Date { now.addingTimeInterval(offset * 3600) }

    @Test func aFailureAfterTheLastSuccessIsFailingAndKeepsTheSuccessTime() {
        var history = SyncHistory()
        history.recordSuccess(.github, at: hours(-3))
        history.recordFailure(.github, error: "401", at: hours(-1))
        let entry = history.sources[.github]!
        #expect(entry.isFailing)
        #expect(entry.lastSuccess == hours(-3))
        #expect(entry.lastError == "401")
    }

    @Test func aSuccessAfterAFailureClearsFailing() {
        var history = SyncHistory()
        history.recordFailure(.calendar, error: "expired", at: hours(-2))
        history.recordSuccess(.calendar, at: hours(-1))
        #expect(!history.sources[.calendar]!.isFailing)
    }

    @Test func failingWithNoSuccessEverIsFailing() {
        var history = SyncHistory()
        history.recordFailure(.github, error: "missing", at: hours(-1))
        #expect(history.sources[.github]!.isFailing)
        #expect(!history.sources[.github]!.syncedToday(now: now))
    }

    @Test func syncedTodayIsByLocalCalendarDay() {
        var history = SyncHistory()
        history.recordSuccess(.github, at: Calendar.current.startOfDay(for: now))
        history.recordSuccess(.calendar, at: Calendar.current.startOfDay(for: now).addingTimeInterval(-1))
        #expect(history.sources[.github]!.syncedToday(now: now))
        #expect(!history.sources[.calendar]!.syncedToday(now: now))
    }

    @Test func sourcesEncodeAsAnObjectKeyedByName() throws {
        var history = SyncHistory()
        history.recordSuccess(.github, at: now)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(history)) as! [String: Any]
        let sources = try #require(json["sources"] as? [String: Any])
        #expect(sources["github"] != nil)
        #expect(try JSONDecoder().decode(SyncHistory.self, from: JSONEncoder().encode(history)) == history)
    }
}

struct BackupScheduleTests {
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 15))!

    private let day: TimeInterval = 24 * 3600

    @Test func dueWhenItHasNeverSucceeded() {
        #expect(Backup.isDue(nil, interval: day, now: now))
        #expect(Backup.isDue(SyncHistory.Entry(lastFailure: now, lastError: "No backup key"), interval: day, now: now))
    }

    @Test func dueAnIntervalAfterTheLastSuccessNotBefore() {
        #expect(!Backup.isDue(SyncHistory.Entry(lastSuccess: now.addingTimeInterval(-23 * 3600)), interval: day, now: now))
        #expect(Backup.isDue(SyncHistory.Entry(lastSuccess: now.addingTimeInterval(-24 * 3600)), interval: day, now: now))
        #expect(!Backup.isDue(SyncHistory.Entry(lastSuccess: now.addingTimeInterval(-5 * 3600)), interval: 6 * 3600, now: now))
        #expect(Backup.isDue(SyncHistory.Entry(lastSuccess: now.addingTimeInterval(-6 * 3600)), interval: 6 * 3600, now: now))
    }
}
