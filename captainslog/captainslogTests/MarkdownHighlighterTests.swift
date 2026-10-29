import AppKit
import Testing
@testable import Captain_s_Log

// The highlighter restyles only the lines an edit touches, then stops once the stored line state
// matches. These check that this always ends where styling the whole text afresh would.
@MainActor
struct MarkdownHighlighterTests {
    private static let sample = """
    # Weekly sync with the payments squad

    Met with **Alice** and _Bob_ about the ledger backfill. See [the design doc](https://example.com/docs/backfill_plan) \
    and https://github.com/example/repo/pull/4521 for context.

    ## Decisions
    - Ship the backfill behind a `ledger.backfill` flag
    - Run it in *small* batches, ~~all at once~~ 10k accounts at a time
        - Monitor the **error rate** on the dashboard
        - Page if it goes above 0.1%
    - Keep the old path until the numbers match

    ## Action items
    - [ ] Write the runbook for the backfill
    - [x] Book the review with the risk team
    - [ ] Ask @Carol about the reconciliation job
    - [ ] Check #4521 lands before Thursday

    1. Dry run in staging
    2. Compare balances
    3. Flip the flag

    > Not every account needs a backfill: closed accounts with a zero balance can be skipped,
    > which roughly halves the work.

    ---

    ```swift
    func backfill(_ accounts: [Account]) async throws {
        for batch in accounts.chunked(into: 10_000) {
            try await ledger.replay(batch)
        }
    }
    ```

    Snake_case_words stay plain, as does a lone * or _.
    """

    private func styled(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage()
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        storage.delegate = nil
        return storage
    }

    private func expectMatchesFresh(_ storage: NSTextStorage, _ comment: Comment? = nil) {
        let fresh = styled(storage.string)
        #expect(storage.isEqual(to: fresh), "\(comment.map { "\($0) " } ?? "")\(firstDifference(storage, fresh))")
    }

    /// Where two stylings of the same text first disagree, to make a failure readable.
    private func firstDifference(_ lhs: NSTextStorage, _ rhs: NSTextStorage) -> String {
        let string = lhs.string as NSString
        for index in 0..<lhs.length {
            let left = lhs.attributes(at: index, effectiveRange: nil) as NSDictionary
            let right = rhs.attributes(at: index, effectiveRange: nil) as NSDictionary
            guard !left.isEqual(to: right as! [AnyHashable: Any]) else { continue }
            let line = string.paragraphRange(for: NSRange(location: index, length: 0))
            let keys = Set(left.allKeys.map { "\($0)" }).union(right.allKeys.map { "\($0)" })
            let differing = keys.filter { key in
                let k = NSAttributedString.Key(key)
                return !((left[k] as? NSObject)?.isEqual(right[k]) ?? (right[k] == nil))
            }
            return "at \(index) in line \(string.substring(with: line).debugDescription): \(differing.sorted()) "
                + "incremental \(differing.map { "\(left[NSAttributedString.Key($0)] ?? "nil")" }) "
                + "fresh \(differing.map { "\(right[NSAttributedString.Key($0)] ?? "nil")" }); text \(lhs.string.debugDescription)"
        }
        return ""
    }

    @Test func openingAFenceRestylesTheLinesBelow() {
        let storage = NSTextStorage()
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "intro\n**bold**\n- item\n```\n")

        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "```\n")
        expectMatchesFresh(storage)
        #expect(storage.attribute(.markdownCodeBlock, at: 6, effectiveRange: nil) != nil)

        // And closing it again releases them.
        storage.replaceCharacters(in: NSRange(location: 0, length: 4), with: "")
        expectMatchesFresh(storage)
        #expect(storage.attribute(.markdownCodeBlock, at: 0, effectiveRange: nil) == nil)
    }

    @Test func typingKeepsTheCaretInPlace() {
        let textView = MarkdownTextView.make()
        let highlighter = MarkdownHighlighter()
        textView.textStorage?.delegate = highlighter
        textView.layoutManager?.delegate = highlighter
        textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "- [ ] alpha **beta** gamma\nnext")

        textView.setSelectedRange(NSRange(location: 8, length: 0))
        textView.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(textView.selectedRange() == NSRange(location: 9, length: 0))

        textView.deleteBackward(nil)
        #expect(textView.selectedRange() == NSRange(location: 8, length: 0))
        #expect(textView.string == "- [ ] alpha **beta** gamma\nnext")
    }

    @Test func randomEditsMatchAFreshStyle() {
        let fragments = [
            "```", "~~~", "\n", "\n\n", "**", "_", "~~", "`", "- ", "- [ ] ", "- [x] ", "1. ", "> ",
            "# ", "## ", "---", "[a](https://b.c)", "https://x.y/z_w", "word", " ", "\\", "é", "🎉",
        ]
        var generator = SeededGenerator(seed: 7)
        let storage = NSTextStorage()
        let highlighter = MarkdownHighlighter()
        storage.delegate = highlighter
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: Self.sample)

        for step in 0..<1000 {
            let length = storage.length
            let location = Int.random(in: 0...length, using: &generator)
            var deleted = Int.random(in: 0...min(6, length - location), using: &generator)
            // Never split a surrogate pair, which a real text view cannot do either.
            let string = storage.mutableString
            var start = location
            if start > 0, start < length, UTF16.isTrailSurrogate(string.character(at: start)) { start -= 1 }
            if start + deleted < length, deleted > 0, UTF16.isTrailSurrogate(string.character(at: start + deleted)) {
                deleted += 1
            }
            let insertion = Bool.random(using: &generator) ? fragments.randomElement(using: &generator)! : ""
            storage.replaceCharacters(in: NSRange(location: start, length: deleted), with: insertion)
            expectMatchesFresh(storage, "step \(step): replaced \(deleted) at \(start) with \(insertion.debugDescription)")
            if !storage.isEqual(to: styled(storage.string)) { break }
        }
    }
}

/// Deterministic, so a failing sequence replays.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
