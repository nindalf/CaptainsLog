import Foundation
import Testing
import CaptainsLogKit

// When an interview gets its "Submit scorecard" todo. Models are built but never inserted.
@Suite(.serialized) @MainActor
struct ScorecardTodoTests {
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 15))!

    private func interview(notes: String? = nil) -> Interview {
        let interview = Interview(date: now, candidateName: "Ada Lovelace")
        interview.rawNotes = notes
        return interview
    }

    @Test func theFirstTextMakesItDue() {
        #expect(ScorecardTodo.isDue(hadText: false, interview: interview(notes: "+ clear"), linkedTodos: []))
    }

    @Test func laterEditsDoNot() {
        #expect(!ScorecardTodo.isDue(hadText: true, interview: interview(notes: "+ clear\nx slow"), linkedTodos: []))
    }

    @Test func clearingTheTextDoesNot() {
        #expect(!ScorecardTodo.isDue(hadText: true, interview: interview(notes: nil), linkedTodos: []))
    }

    @Test func anyLinkedTodoBlocksIt() {
        let trashed = Todo(title: "Submit scorecard for Ada Lovelace")
        trashed.moveToTrash()
        #expect(!ScorecardTodo.isDue(hadText: false, interview: interview(notes: "+ clear"), linkedTodos: [trashed]))
    }

    @Test func nonTextFieldsDoNotCount() {
        let item = interview()
        item.recommendation = .yes
        #expect(!ScorecardTodo.isDue(hadText: false, interview: item, linkedTodos: []))
    }

    @Test func theTodoIsForTodayAboveEverything() {
        let other = Todo(title: "other")
        other.sortOrder = 3
        let todo = ScorecardTodo.make(for: interview(), among: [other], now: now)
        #expect(todo.title == "Submit scorecard for Ada Lovelace")
        #expect(SmartList.of(todo, now: now) == .today)
        #expect(todo.sortOrder < other.sortOrder)
    }

    @Test func aPrivateInterviewStillGivesASharedTodo() {
        let item = interview()
        item.isPrivate = true
        #expect(!ScorecardTodo.make(for: item, among: [], now: now).isPrivate)
    }

    @Test func aBlankCandidateDropsTheName() {
        let item = Interview(date: now, candidateName: "  ")
        #expect(ScorecardTodo.title(for: item) == "Submit scorecard")
    }
}
