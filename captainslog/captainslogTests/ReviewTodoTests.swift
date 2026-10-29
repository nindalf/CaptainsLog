import Foundation
import Testing
import CaptainsLogKit

// The "Review PR" todo filed from a review request. Models are built but never inserted.
@Suite(.serialized) @MainActor
struct ReviewTodoTests {
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 15))!

    private func pr(title: String) -> PullRequest {
        PullRequest(
            number: 42, title: title, url: URL(string: "https://github.com/larder/fulfilment/pull/42")!,
            repo: "larder/fulfilment", state: .open, createdAt: .now, isAuthoredByMe: false
        )
    }

    @Test func aShortTitleIsKeptWhole() {
        #expect(ReviewTodo.title(for: pr(title: "Add retries to screening")) == "Review PR Add retries to screening")
    }

    @Test func aLongTitleIsClipped() {
        let long = "Migrate the screening pipeline to the new rules engine and drop the legacy matcher"
        let title = ReviewTodo.title(for: pr(title: long))
        #expect(title.hasPrefix("Review PR Migrate the screening pipeline"))
        #expect(title.hasSuffix("…"))
        #expect(title.count < long.count)
    }

    @Test func theTodoIsForTodayAboveEverythingWithTheURL() {
        let other = Todo(title: "other")
        other.sortOrder = 3
        let todo = ReviewTodo.make(for: pr(title: "Fix flaky test"), among: [other], now: now)
        #expect(todo.notes == "https://github.com/larder/fulfilment/pull/42")
        #expect(SmartList.of(todo, now: now) == .today)
        #expect(todo.sortOrder < other.sortOrder)
    }
}
