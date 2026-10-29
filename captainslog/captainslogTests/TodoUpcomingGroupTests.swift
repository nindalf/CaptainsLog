import Foundation
import Testing
import CaptainsLogKit
@testable import Captain_s_Log

// Date bucketing only. Todos are built but never inserted, so no container is needed.
@Suite(.serialized) @MainActor
struct TodoUpcomingGroupTests {
    /// Saturday 17 Oct 2026.
    private let now = date(2026, 10, 17)

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Self.date(year, month, day)
    }

    private func todo(_ title: String, due: Date, sortOrder: Int = 0) -> Todo {
        let todo = Todo(title: title, dueDate: Calendar.current.startOfDay(for: due))
        todo.sortOrder = sortOrder
        return todo
    }

    @Test func theNextSixDaysGetDayLabels() {
        let groups = TodoUpcomingGroup.group([
            todo("sun", due: date(2026, 10, 18)),
            todo("mon", due: date(2026, 10, 19)),
            todo("fri", due: date(2026, 10, 23)),
        ], now: now)

        #expect(groups.map(\.label) == ["Tomorrow", "Monday 19 Oct", "Friday 23 Oct"])
    }

    @Test func laterDatesAreGroupedByMonth() {
        let groups = TodoUpcomingGroup.group([
            todo("next sat", due: date(2026, 10, 24)),
            todo("end of oct", due: date(2026, 10, 30)),
            todo("nov", due: date(2026, 11, 3)),
        ], now: now)

        #expect(groups.map(\.label) == ["October", "November"])
        #expect(groups[0].todos.map(\.title) == ["next sat", "end of oct"])
    }

    @Test func theRestOfThisMonthComesAfterTheDayGroups() {
        let groups = TodoUpcomingGroup.group([
            todo("end of oct", due: date(2026, 10, 30)),
            todo("tue", due: date(2026, 10, 20)),
        ], now: now)

        #expect(groups.map(\.label) == ["Tuesday 20 Oct", "October"])
    }

    @Test func otherYearsAreDisambiguatedByYear() {
        let groups = TodoUpcomingGroup.group([todo("jan", due: date(2027, 1, 5))], now: now)
        #expect(groups.map(\.label) == ["January 2027"])
    }

    @Test func groupsAreChronologicalAndTiesFallBackToSortOrder() {
        let groups = TodoUpcomingGroup.group([
            todo("dec", due: date(2026, 12, 1)),
            todo("tomorrow b", due: date(2026, 10, 18), sortOrder: 2),
            todo("tomorrow a", due: date(2026, 10, 18), sortOrder: 1),
        ], now: now)

        #expect(groups.map(\.label) == ["Tomorrow", "December"])
        #expect(groups[0].todos.map(\.title) == ["tomorrow a", "tomorrow b"])
    }

    // Dropping: the date a todo takes from where it lands.

    /// `index` is the position among the other items, with `moved` taken out.
    private func dropDate(_ moved: Todo, in todos: [Todo], to index: Int) -> Date? {
        let groups = TodoUpcomingGroup.group(todos, now: now)
        var items = TodoUpcomingGroup.items(groups)
        items.removeAll { $0 == .todo(moved.id) }
        items.insert(.todo(moved.id), at: index)
        return TodoUpcomingGroup.dueDate(for: moved.id, droppedIn: items, groups: groups)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.startOfDay(for: date(year, month, day))
    }

    @Test func droppingUnderAnotherDayTakesThatDay() {
        let sun = todo("sun", due: date(2026, 10, 18))
        let mon = todo("mon", due: date(2026, 10, 19))
        // [Tomorrow, Monday, mon] -> sun goes below mon.
        #expect(dropDate(sun, in: [sun, mon], to: 3) == day(2026, 10, 19))
    }

    @Test func reorderingWithinADayKeepsTheDate() {
        let a = todo("a", due: date(2026, 10, 18), sortOrder: 1)
        let b = todo("b", due: date(2026, 10, 18), sortOrder: 2)
        // [Tomorrow, a] -> b goes above a.
        #expect(dropDate(b, in: [a, b], to: 1) == day(2026, 10, 18))
    }

    @Test func droppingIntoAMonthTakesTheDateAboveOrTheFirstDay() {
        let tue = todo("tue", due: date(2026, 10, 20))
        let nov3 = todo("nov 3", due: date(2026, 11, 3))
        let nov20 = todo("nov 20", due: date(2026, 11, 20))
        let all = [tue, nov3, nov20]
        // [Tuesday, November, nov 3, nov 20]
        #expect(dropDate(tue, in: all, to: 2) == day(2026, 11, 1))
        #expect(dropDate(tue, in: all, to: 3) == day(2026, 11, 3))
        #expect(dropDate(tue, in: all, to: 4) == day(2026, 11, 20))
    }

    @Test func aMonthTodoKeepsItsDateIfItStillSortsThere() {
        let nov3 = todo("nov 3", due: date(2026, 11, 3))
        let nov10 = todo("nov 10", due: date(2026, 11, 10))
        let nov20 = todo("nov 20", due: date(2026, 11, 20))
        // [November, nov 3, nov 20]: nov 10 dropped back between its neighbours.
        #expect(dropDate(nov10, in: [nov3, nov10, nov20], to: 2) == day(2026, 11, 10))
        // Above nov 3 it must move to sort there.
        #expect(dropDate(nov10, in: [nov3, nov10, nov20], to: 1) == day(2026, 11, 1))
    }

    @Test func theRestOfThisMonthStartsAfterTheDayGroups() {
        let tue = todo("tue", due: date(2026, 10, 20))
        let oct30 = todo("end of oct", due: date(2026, 10, 30))
        // [Tuesday, October, end of oct] -> tue goes to the top of October.
        #expect(dropDate(tue, in: [tue, oct30], to: 2) == day(2026, 10, 24))
    }
}
