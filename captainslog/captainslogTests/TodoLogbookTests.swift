import Foundation
import Testing
import CaptainsLogKit
@testable import Captain_s_Log

// Date bucketing only. Todos are built but never inserted, so no container is needed.
@Suite(.serialized) @MainActor
struct TodoLogbookTests {
    /// 4 Aug 2026, matching the day the logbook layout was specced.
    private let now = date(2026, 8, 4)

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Self.date(year, month, day)
    }

    private func todo(_ title: String, completed: Date) -> Todo {
        let todo = Todo(title: title)
        todo.completedDate = completed
        return todo
    }

    @Test func reopeningAsksOnlyForTodosCompletedBeforeToday() {
        let startOfToday = Calendar.current.startOfDay(for: now)
        #expect(!Todo.reopenNeedsConfirmation([todo("this morning", completed: startOfToday)], now: now))
        #expect(Todo.reopenNeedsConfirmation([todo("last night", completed: startOfToday.addingTimeInterval(-1))], now: now))
        #expect(!Todo.reopenNeedsConfirmation([Todo(title: "open")], now: now))
        #expect(Todo.reopenNeedsConfirmation([todo("today", completed: now), todo("july", completed: date(2026, 7, 31))], now: now))
    }

    @Test func recentDaysGetRelativeLabelsAndOlderOnesGetMonths() {
        let groups = TodoLogbookGroup.group([
            todo("today", completed: now),
            todo("yesterday", completed: date(2026, 8, 3)),
            todo("july", completed: date(2026, 7, 31)),
        ], now: now)

        #expect(groups.map(\.label) == ["Today", "Yesterday", "July"])
    }

    @Test func aMonthGroupCollectsEveryDayInIt() {
        let groups = TodoLogbookGroup.group([
            todo("2 jul", completed: date(2026, 7, 2)),
            todo("31 jul", completed: date(2026, 7, 31)),
            todo("16 jul", completed: date(2026, 7, 16)),
        ], now: now)

        #expect(groups.count == 1)
        #expect(groups[0].label == "July")
        // Newest first within the group.
        #expect(groups[0].todos.map(\.title) == ["31 jul", "16 jul", "2 jul"])
    }

    @Test func earlierYearsAreDisambiguatedByYear() {
        let groups = TodoLogbookGroup.group([
            todo("this july", completed: date(2026, 7, 5)),
            todo("last july", completed: date(2025, 7, 5)),
        ], now: now)

        #expect(groups.map(\.label) == ["July", "July 2025"])
    }

    @Test func groupsAreOrderedNewestFirstAcrossAYearBoundary() {
        let groups = TodoLogbookGroup.group([
            todo("dec", completed: date(2025, 12, 20)),
            todo("jan", completed: date(2026, 1, 8)),
            todo("jul", completed: date(2026, 7, 5)),
        ], now: now)

        #expect(groups.map(\.label) == ["July", "January", "December 2025"])
    }

    @Test func completedProjectsAreListedAmongTodosByDate() {
        let project = Project(name: "Launch")
        project.completedDate = date(2026, 7, 20)
        let groups = TodoLogbookGroup.group(
            [todo("31 jul", completed: date(2026, 7, 31)), todo("2 jul", completed: date(2026, 7, 2))],
            projects: [project],
            now: now
        )

        #expect(groups.count == 1)
        #expect(groups[0].entries.map(\.id) == [groups[0].todos[0].id, project.id, groups[0].todos[1].id])
    }
}
