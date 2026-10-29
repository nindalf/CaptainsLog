import Foundation
import Testing
import CaptainsLogKit

// List membership and moves. Todos are built but never inserted, so no container is needed.
@Suite(.serialized) @MainActor
struct SmartListTests {
    /// Saturday 17 Oct 2026, midday.
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!

    private func day(_ offset: Int, hour: Int = 9) -> Date {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
        return cal.date(byAdding: .hour, value: hour, to: start)!
    }

    private func todo(due: Date? = nil, schedule: TodoSchedule = .anytime, completed: Bool = false, project: Project? = nil) -> Todo {
        let todo = Todo(title: "t", dueDate: due)
        todo.schedule = schedule
        todo.completedDate = completed ? .now : nil
        todo.project = project
        return todo
    }

    private func lists(showing item: Todo) -> [SmartList] {
        SmartList.allCases.filter { $0.contains(item, now: now) }
    }

    @Test func undatedTodosWithoutAProjectAreInTheInboxWhateverTheSchedule() {
        #expect(SmartList.of(todo(schedule: .inbox), now: now) == .inbox)
        #expect(SmartList.of(todo(schedule: .anytime), now: now) == .inbox)
    }

    @Test func undatedTodosInAProjectAreInAnytime() {
        #expect(SmartList.of(todo(project: Project(name: "P")), now: now) == .anytime)
    }

    @Test func somedayOutranksAProject() {
        let item = todo(schedule: .someday, project: Project(name: "P"))
        #expect(lists(showing: item) == [.someday])
    }

    @Test func anytimeAlsoShowsDatedTodos() {
        #expect(lists(showing: todo(due: day(0))) == [.today, .anytime])
        #expect(lists(showing: todo(due: day(5))) == [.upcoming, .anytime])
        #expect(lists(showing: todo()) == [.inbox])
    }

    @Test func todayAndOverdueAreToday() {
        #expect(SmartList.of(todo(due: day(0, hour: 23)), now: now) == .today)
        #expect(SmartList.of(todo(due: day(-30)), now: now) == .today)
    }

    @Test func futureDatesAreUpcoming() {
        #expect(SmartList.of(todo(due: day(1, hour: 0)), now: now) == .upcoming)
        #expect(SmartList.of(todo(due: day(90)), now: now) == .upcoming)
    }

    @Test func aDateOutranksTheSchedule() {
        #expect(SmartList.of(todo(due: day(0), schedule: .someday), now: now) == .today)
        #expect(SmartList.of(todo(due: day(3), schedule: .inbox), now: now) == .upcoming)
    }

    @Test func completedTodosAreInTheLogbookWhateverTheirDate() {
        #expect(SmartList.of(todo(due: day(0), completed: true), now: now) == .logbook)
        #expect(SmartList.of(todo(schedule: .inbox, completed: true), now: now) == .logbook)
    }

    @Test func completedAndTrashedTodosAreNotInAnytime() {
        let dated = todo(due: day(0), completed: true)
        let trashed = todo(due: day(0))
        trashed.moveToTrash(now: now)
        #expect(lists(showing: dated) == [.logbook])
        #expect(lists(showing: trashed) == [.trash])
    }

    @Test func movingPutsTheTodoInThatList() {
        for list in SmartList.allCases where list.acceptsTodos {
            let item = todo(due: day(-2), schedule: .someday)
            list.move(item, now: now)
            #expect(SmartList.of(item, now: now) == list, "moved to \(list)")
        }
    }

    @Test func movingToTodayStoresStartOfDay() {
        let item = todo(schedule: .inbox)
        SmartList.today.move(item, now: now)
        #expect(item.dueDate == Calendar.current.startOfDay(for: now))
    }

    @Test func schedulingASomedayTodoEndsSomeday() {
        let item = todo(schedule: .someday)
        item.schedule(on: day(4))
        item.dueDate = nil
        #expect(SmartList.of(item, now: now) == .inbox)
    }

    @Test func trashedTodosAreInTheTrashWhateverElseIsSet() {
        let dated = todo(due: day(0))
        let done = todo(completed: true)
        dated.moveToTrash(now: now)
        done.moveToTrash(now: now)
        #expect(SmartList.of(dated, now: now) == .trash)
        #expect(SmartList.of(done, now: now) == .trash)
    }

    @Test func restoringReturnsATodoToItsOriginalList() {
        let someday = todo(schedule: .someday)
        let upcoming = todo(due: day(3))
        let done = todo(completed: true)
        for item in [someday, upcoming, done] {
            item.moveToTrash(now: now)
            item.restoreFromTrash()
        }
        #expect(SmartList.of(someday, now: now) == .someday)
        #expect(SmartList.of(upcoming, now: now) == .upcoming)
        #expect(SmartList.of(done, now: now) == .logbook)
    }

    @Test func movingToTheLogbookDoesNothing() {
        let item = todo(schedule: .inbox)
        SmartList.logbook.move(item, now: now)
        #expect(SmartList.of(item, now: now) == .inbox)
    }
}

@Suite(.serialized) @MainActor
struct TodoWhenTests {
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: .now) }

    @Test func aDayIsReadAtStartOfDay() {
        let todo = Todo(title: "t", dueDate: cal.date(byAdding: .hour, value: 15, to: today))
        #expect(TodoWhen.of(todo) == .day(today))
    }

    @Test func choosingADayEndsSomeday() {
        let todo = Todo(title: "t")
        TodoWhen.someday.apply(to: todo)
        TodoWhen.day(today).apply(to: todo)
        #expect(TodoWhen.of(todo) == .day(today))
        #expect(todo.schedule != .someday)
    }

    @Test func choosingSomedayOrClearingRemovesTheDate() {
        let parked = Todo(title: "t", dueDate: today)
        let cleared = Todo(title: "t", dueDate: today)
        TodoWhen.someday.apply(to: parked)
        TodoWhen.unset.apply(to: cleared)
        #expect(TodoWhen.of(parked) == .someday)
        #expect(TodoWhen.of(cleared) == .unset)
        #expect(SmartList.of(cleared) == .inbox)
    }

    @Test func aSelectionHasAWhenOnlyWhenItsTodosAgree() {
        let a = Todo(title: "a", dueDate: today)
        let b = Todo(title: "b", dueDate: today)
        let c = Todo(title: "c")
        #expect(TodoWhen.common(to: [a, b]) == .day(today))
        #expect(TodoWhen.common(to: [a, c]) == nil)
    }
}
