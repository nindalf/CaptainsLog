import Testing
import Foundation
import CaptainsLogKit

struct MentionsTests {
    private let alice = Person(name: "Alice Smith", slackHandle: "alice", githubHandle: "asmith")
    private let alex = Person(name: "Alex")
    private let bob = Person(name: "Bob Jones", slackHandle: "bob.jones")

    private var everyone: [Person] { [alice, alex, bob] }

    private func names(_ text: String) -> [String] {
        Mentions.people(in: text, among: everyone).map(\.name)
    }

    @Test func matchesSlackHandleGitHubHandleAndName() {
        #expect(names("Ask @alice") == ["Alice Smith"])
        #expect(names("Ask @asmith") == ["Alice Smith"])
        #expect(names("Ask @Alice Smith about it") == ["Alice Smith"])
        #expect(names("Ask @alex") == ["Alex"])
    }

    @Test func isCaseInsensitive() {
        #expect(names("@ALICE and @alex") == ["Alice Smith", "Alex"])
    }

    @Test func tagEndsAtPunctuationButNotInsideAHandle() {
        #expect(names("Thank @alice, @alex. And @alice's doc?") == ["Alice Smith", "Alex"])
        #expect(names("Ping @bob.jones.") == ["Bob Jones"])
        #expect(names("@alicex and @alice-two and @alice.smith").isEmpty)
    }

    @Test func ignoresEmailsAndUnknownTags() {
        #expect(names("mail alice@example.com").isEmpty)
        #expect(names("Ask @carol").isEmpty)
    }

    @Test func longestMatchWins() {
        let al = Person(name: "Al")
        let people = [al, alice]
        #expect(Mentions.people(in: "@alice", among: people).map(\.name) == ["Alice Smith"])
        #expect(Mentions.people(in: "@al", among: people).map(\.name) == ["Al"])
    }

    @Test func duplicatesWithTheSameNameAllMatch() {
        let other = Person(name: "Alex")
        #expect(Mentions.people(in: "@Alex", among: [alex, other]).count == 2)
    }

    @Test func linksTitleAndNotesTagsAndUnlinksRemovedOnes() {
        let todo = Todo(title: "Talk to @alice")
        todo.notes = "Loop in @bob.jones too"
        #expect(todo.linkMentionedPeople(among: everyone))
        #expect(Set(todo.people.map(\.name)) == ["Alice Smith", "Bob Jones"])
        #expect(!todo.linkMentionedPeople(among: everyone))

        todo.notes = nil
        #expect(todo.linkMentionedPeople(among: everyone))
        #expect(todo.people.map(\.name) == ["Alice Smith"])

        todo.title = "Talk to someone"
        todo.linkMentionedPeople(among: everyone)
        #expect(todo.people.isEmpty)
    }

    @Test func linksLogEntryTitleAndContentTags() {
        let entry = LogEntry(timestamp: .now, source: .manual, title: "Pairing with @alex", content: "")
        #expect(entry.linkMentionedPeople(among: everyone))
        #expect(entry.people.map(\.name) == ["Alex"])

        entry.content = "Then @alice reviewed it"
        entry.title = "Pairing"
        #expect(entry.linkMentionedPeople(among: everyone))
        #expect(entry.people.map(\.name) == ["Alice Smith"])
    }
}
