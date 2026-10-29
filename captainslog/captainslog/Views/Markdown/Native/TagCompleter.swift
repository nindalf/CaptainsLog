import AppKit
import Carbon.HIToolbox
import SwiftData
import CaptainsLogKit

/// `@` / `#` completion for a text view: the native markdown editor's own, or the field editor
/// behind a title `TextField`. Owns the suggestion list while it is open.
final class TagCompleter {
    weak var textView: NSTextView?
    var modelContext: ModelContext?

    private enum Candidate {
        case person(Person)
        case pullRequest(PullRequest)

        var insertion: String {
            switch self {
            case let .person(person): mentionInsertion(name: person.name, slackHandle: person.slackHandle)
            case let .pullRequest(pullRequest): pullRequestInsertion(number: pullRequest.number)
            }
        }

        var row: MarkdownCompletionRow {
            switch self {
            case let .person(person):
                MarkdownCompletionRow(
                    id: person.id,
                    title: person.name,
                    detail: (person.slackHandle ?? person.githubHandle).map { "@\($0)" }
                )
            case let .pullRequest(pullRequest):
                // Only the number is inserted, so the row carries the repo to tell apart PRs with
                // the same number.
                MarkdownCompletionRow(
                    id: pullRequest.id,
                    leading: "#\(pullRequest.number)",
                    title: pullRequest.title,
                    trailing: pullRequest.repo
                )
            }
        }
    }

    private struct Session {
        let trigger: CompletionTrigger
        /// UTF-16 offset of the trigger character.
        let start: Int
        var prefix = ""
        var candidates: [Candidate] = []
        var selected = 0
    }

    private static let maximumSuggestions = 6

    private var session: Session?
    // Fetched when a list opens and kept until it closes, so typing a prefix does not refetch.
    private var people: [Person]?
    private var pullRequests: [PullRequest]?
    private var keyMonitor: Any?

    private var isCompleting: Bool {
        session.map { !$0.candidates.isEmpty } ?? false
    }

    /// Open, refresh or close the list for the token before the caret. Call after every edit and
    /// selection change.
    func update() {
        guard let textView, textView.window?.firstResponder === textView, !textView.hasMarkedText() else {
            end()
            return
        }
        let selection = textView.selectedRange()
        guard selection.length == 0 else {
            end()
            return
        }
        let caret = selection.location
        let before = textView.lineTextBefore(caret)
        guard let query = completionQuery(in: before, caretOffset: before.count) else {
            end()
            return
        }

        let start = caret - 1 - query.prefix.utf16.count
        if session?.trigger != query.trigger || session?.start != start {
            session = Session(trigger: query.trigger, start: start)
        }
        if session?.prefix != query.prefix || session?.candidates.isEmpty == true {
            session?.prefix = query.prefix
            session?.candidates = candidates(for: query)
            session?.selected = 0
        }
        show()
    }

    func end() {
        guard session != nil || people != nil || pullRequests != nil || keyMonitor != nil else { return }
        session = nil
        people = nil
        pullRequests = nil
        MarkdownCompletionPanel.shared.hide(owner: self)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func candidates(for query: CompletionQuery) -> [Candidate] {
        guard let modelContext else { return [] }
        switch query.trigger {
        case .person:
            if people == nil {
                people = (try? modelContext.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.name)]))) ?? []
            }
            var scored: [(person: Person, score: Int)] = []
            for person in people ?? [] {
                guard let score = mentionMatchScore(
                    prefix: query.prefix, name: person.name, handles: [person.slackHandle, person.githubHandle]
                ) else { continue }
                scored.append((person, score))
            }
            scored.sort { $0.score == $1.score ? $0.person.name < $1.person.name : $0.score < $1.score }
            return scored.prefix(Self.maximumSuggestions).map { .person($0.person) }
        case .pullRequest:
            if pullRequests == nil {
                pullRequests = (try? modelContext.fetch(FetchDescriptor<PullRequest>())) ?? []
            }
            var scored: [(pullRequest: PullRequest, score: Int)] = []
            for pullRequest in pullRequests ?? [] {
                guard let score = pullRequestMatchScore(
                    prefix: query.prefix, number: pullRequest.number, title: pullRequest.title, repo: pullRequest.repo
                ) else { continue }
                scored.append((pullRequest, score))
            }
            scored.sort {
                pullRequestSuggestionPrecedes(
                    (score: $0.score, number: $0.pullRequest.number),
                    (score: $1.score, number: $1.pullRequest.number)
                )
            }
            return scored.prefix(Self.maximumSuggestions).map { .pullRequest($0.pullRequest) }
        }
    }

    private func show() {
        guard let session, !session.candidates.isEmpty, let textView, let window = textView.window else {
            MarkdownCompletionPanel.shared.hide(owner: self)
            return
        }
        let caret = textView.firstRect(forCharacterRange: NSRange(location: session.start, length: 0), actualRange: nil)
        MarkdownCompletionPanel.shared.show(
            rows: session.candidates.map(\.row),
            selected: session.selected,
            caret: caret,
            parent: window,
            owner: self
        ) { [weak self] index in
            self?.accept(index)
        }
        installKeyMonitor()
    }

    /// While the list is open, its keys reach it ahead of anything else. SwiftUI hands Return and
    /// Escape to a Todo or Log list, or a title field's submit, before the text view, which would
    /// close the card instead.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let textView, event.window?.firstResponder === textView, handleKey(event) else { return event }
            return nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab: return acceptSelected()
        case kVK_Escape: return cancel()
        case kVK_UpArrow: return move(by: -1)
        case kVK_DownArrow: return move(by: 1)
        default: return false
        }
    }

    private func move(by delta: Int) -> Bool {
        guard isCompleting, var session else { return false }
        session.selected = min(max(session.selected + delta, 0), session.candidates.count - 1)
        self.session = session
        MarkdownCompletionPanel.shared.select(session.selected)
        return true
    }

    private func acceptSelected() -> Bool {
        guard isCompleting, let session else { return false }
        accept(session.selected)
        return true
    }

    private func cancel() -> Bool {
        guard isCompleting else { return false }
        end()
        return true
    }

    private func accept(_ index: Int) {
        guard let session, session.candidates.indices.contains(index), let textView else { return }
        let caret = textView.selectedRange().location
        guard caret > session.start else {
            end()
            return
        }
        var insertion = session.candidates[index].insertion
        // The caret lands after the trailing space either way. Completing mid-text before an
        // existing space reuses that space rather than doubling it.
        let caretAfter = session.start + insertion.utf16.count
        if let storage = textView.textStorage, caret < storage.length,
           storage.mutableString.character(at: caret) == 0x20, insertion.hasSuffix(" ") {
            insertion.removeLast()
        }
        end()
        textView.replace(
            NSRange(location: session.start, length: caret - session.start),
            with: insertion,
            select: NSRange(location: caretAfter, length: 0)
        )
    }
}

extension NSTextView {
    /// Replace `range` as one undoable edit, notifying the delegate as typing would.
    func replace(_ range: NSRange, with string: String, select selection: NSRange) {
        breakUndoCoalescing()
        guard shouldChangeText(in: range, replacementString: string) else { return }
        textStorage?.replaceCharacters(in: range, with: string)
        didChangeText()
        setSelectedRange(selection)
        breakUndoCoalescing()
    }

    /// The line's text before `caret`. A tag is at most a trigger and a 32-character prefix, so
    /// a short window is enough.
    func lineTextBefore(_ caret: Int) -> String {
        guard let string = textStorage?.mutableString else { return "" }
        let lineStart = string.paragraphRange(for: NSRange(location: caret, length: 0)).location
        let from = max(lineStart, caret - 80)
        return string.substring(with: NSRange(location: from, length: caret - from))
    }

    /// `@alice 's` becomes `@alice's` and `@alice ?` becomes `@alice?`: see `possessiveJoin`
    /// and `punctuationJoin`. Call only after typed text, so undoing a join restores the space
    /// for good.
    func joinTagBeforeCaret() {
        let selection = selectedRange()
        guard selection.length == 0, !hasMarkedText(), let storage = textStorage else { return }
        let caret = selection.location
        let string = storage.mutableString
        guard caret >= 3 else { return }
        let lastTwo = Array(string.substring(with: NSRange(location: caret - 2, length: 2)))
        guard lastTwo.count == 2 else { return }
        let possessive = mayEndPossessive(apostrophe: lastTwo[0], last: lastTwo[1])
        guard possessive || mayEndPunctuation(space: lastTwo[0], last: lastTwo[1]) else { return }
        let before = lineTextBefore(caret)
        // The space, apostrophe and punctuation are one UTF-16 unit each, so either join shortens by one.
        if possessive {
            guard let join = possessiveJoin(in: before, caretOffset: before.count) else { return }
            let space = caret - String(before.dropFirst(join.start)).utf16.count
            replace(NSRange(location: space, length: 2), with: join.replacement, select: NSRange(location: caret - 1, length: 0))
        } else {
            guard punctuationJoin(in: before, caretOffset: before.count) != nil else { return }
            replace(NSRange(location: caret - 2, length: 1), with: "", select: NSRange(location: caret - 1, length: 0))
        }
    }
}
