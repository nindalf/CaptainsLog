import Foundation
import Testing
import CaptainsLogKit

// Pure logic, so no container and parallel execution is fine.
struct MarkdownLineScannerTests {
    /// The text of each styled run with its style.
    private func runs(_ line: String, entry: MarkdownLineState = .normal) -> [(String, MarkdownInlineStyle)] {
        let units = Array(line.utf16)
        return scanMarkdownLine(line, entry: entry).runs.map {
            (String(decoding: units[$0.range], as: UTF16.self), $0.style)
        }
    }

    /// The text carrying `style`, joined across runs.
    private func text(_ line: String, with style: MarkdownInlineStyle) -> String {
        let units = Array(line.utf16)
        var result: [UInt16] = []
        for run in scanMarkdownLine(line).runs where run.style.contains(style) {
            result += units[run.range]
        }
        return String(decoding: result, as: UTF16.self)
    }

    // MARK: Emphasis

    @Test func strongAndEmphasis() {
        #expect(text("a **bold** b", with: .strong) == "**bold**")
        #expect(text("a _it_ b", with: .emphasis) == "_it_")
        #expect(text("a *it* b", with: .emphasis) == "*it*")
        #expect(text("a **bold** b", with: .syntax) == "****")
    }

    @Test func nestedEmphasis() {
        #expect(text("***both***", with: .strong) == "**both**")
        #expect(text("***both***", with: .emphasis) == "***both***")
        #expect(text("**a _b_ c**", with: .emphasis) == "_b_")
    }

    @Test func ruleOfThree() {
        // CommonMark example: the inner `**` closes the outer `*`'s run only by the rule of three.
        #expect(text("*foo**bar**baz*", with: .emphasis) == "*foo**bar**baz*")
        #expect(text("*foo**bar**baz*", with: .strong) == "**bar**")
    }

    @Test func intrawordUnderscoresStayPlain() {
        #expect(text("snake_case_word", with: .emphasis).isEmpty)
        #expect(text("2*3*4", with: .emphasis) == "*3*")
    }

    @Test func unmatchedDelimitersStayPlain() {
        #expect(scanMarkdownLine("a * b").runs.isEmpty)
        #expect(scanMarkdownLine("**open").runs.isEmpty)
        #expect(scanMarkdownLine("closed** here").runs.isEmpty)
    }

    @Test func strikethrough() {
        #expect(text("~~gone~~ now", with: .strikethrough) == "~~gone~~")
        #expect(text("~~~not~~~", with: .strikethrough).isEmpty)
    }

    // MARK: Code, escapes, links

    @Test func codeSpanMasksMarkup() {
        #expect(text("run `**x**` now", with: .code) == "`**x**`")
        #expect(text("run `**x**` now", with: .strong).isEmpty)
        #expect(text("``a ` b``", with: .code) == "``a ` b``")
        #expect(text("a ` b", with: .code).isEmpty)
    }

    @Test func escapes() {
        #expect(text(#"\*not\*"#, with: .emphasis).isEmpty)
        #expect(text(#"\*not\*"#, with: .syntax) == #"\\"#)
    }

    @Test func inlineLink() {
        let line = "see [the doc](https://example.com/a_b) now"
        #expect(text(line, with: .link) == "the doc")
        #expect(text(line, with: .syntax) == "[](https://example.com/a_b)")
        #expect(text(line, with: .emphasis).isEmpty)
        let links = scanMarkdownLine(line).links
        #expect(links.map(\.destination) == ["https://example.com/a_b"])
    }

    @Test func linkWithTitleAndEmphasisInText() {
        let line = #"[**bold** link](https://x.com "Title")"#
        #expect(text(line, with: .strong) == "**bold**")
        #expect(scanMarkdownLine(line).links.first?.destination == "https://x.com")
    }

    @Test func bareURLs() {
        let line = "(see https://x.com/a_b_c). Then"
        #expect(text(line, with: .link) == "https://x.com/a_b_c")
        #expect(text(line, with: .emphasis).isEmpty)
        #expect(text("<https://x.com>", with: .link) == "https://x.com")
        #expect(text("<https://x.com>", with: .syntax) == "<>")
        #expect(text("nohttps://x.com", with: .link).isEmpty)
    }

    // MARK: Blocks

    @Test func headings() {
        #expect(scanMarkdownLine("## Key ##").block == .heading(level: 2))
        #expect(text("## Key ##", with: .syntax) == "## ##")
        #expect(scanMarkdownLine("#hashtag").block == .paragraph)
        #expect(scanMarkdownLine("####### seven").block == .paragraph)
        #expect(scanMarkdownLine("#").block == .heading(level: 1))
    }

    @Test func rules() {
        #expect(scanMarkdownLine("---").block == .rule)
        #expect(scanMarkdownLine("- - -").block == .rule)
        #expect(scanMarkdownLine("***").block == .paragraph)
        #expect(scanMarkdownLine("___").block == .paragraph)
        #expect(scanMarkdownLine("--").block == .paragraph)
        #expect(scanMarkdownLine("- - x").block == .paragraph)
    }

    @Test func bulletsAndOrderedItems() {
        let bullet = scanMarkdownLine("  - item")
        #expect(bullet.list?.kind == .bullet)
        #expect(bullet.list?.indent == 2)
        #expect(bullet.list?.range == 2..<4)
        #expect(bullet.contentStart == 4)

        let ordered = scanMarkdownLine("12) twelve")
        #expect(ordered.list?.kind == .ordered(number: 12, delimiter: 0x29))
        #expect(ordered.contentStart == 4)

        #expect(scanMarkdownLine("-not a list").list == nil)
        #expect(scanMarkdownLine("-").list?.kind == .bullet)
    }

    @Test func tasks() {
        let open = scanMarkdownLine("- [ ] write it")
        #expect(open.list?.task?.range == 2..<5)
        #expect(open.list?.task?.isChecked == false)
        #expect(open.contentStart == 6)
        #expect(scanMarkdownLine("- [x] done").list?.task?.isChecked == true)
        #expect(scanMarkdownLine("- [X] done").list?.task?.isChecked == true)
        #expect(scanMarkdownLine("1. [ ] first").list?.task != nil)
        #expect(scanMarkdownLine("- [ ]").list?.task != nil)
        #expect(scanMarkdownLine("- [y] no").list?.task == nil)
        #expect(scanMarkdownLine("- [ ]x").list?.task == nil)
        #expect(scanMarkdownLine("[ ] no bullet").list == nil)
    }

    @Test func quotes() {
        let nested = scanMarkdownLine("> > - [ ] deep")
        #expect(nested.quoteMarkers == [0, 2])
        #expect(nested.list?.task != nil)
        #expect(nested.contentStart == 10)
        #expect(scanMarkdownLine("> # Title").block == .heading(level: 1))
    }

    // MARK: Fences

    @Test func fencesCarryState() {
        let open = scanMarkdownLine("```swift")
        #expect(open.block == .fenceOpen)
        guard case let .inFence(fence) = open.exit else {
            Issue.record("fence did not open")
            return
        }
        #expect(fence.length == 3)

        let inside = scanMarkdownLine("**not bold**", entry: open.exit)
        #expect(inside.block == .code)
        #expect(inside.runs.isEmpty)
        #expect(inside.exit == open.exit)

        #expect(scanMarkdownLine("~~~", entry: open.exit).block == .code)
        #expect(scanMarkdownLine("``", entry: open.exit).block == .code)
        let close = scanMarkdownLine("  ````  ", entry: open.exit)
        #expect(close.block == .fenceClose)
        #expect(close.exit == .normal)
    }

    @Test func backtickInInfoStringIsNotAFence() {
        #expect(scanMarkdownLine("```a```").block == .paragraph)
        #expect(scanMarkdownLine("~~~ a`b").block == .fenceOpen)
    }

    @Test func exitMatchesFullScan() {
        let lines = ["text", "```", "code", "~~~", "````", "```", "inside", "```"]
        var entry = MarkdownLineState.normal
        for line in lines {
            let units = Array(line.utf16)
            let quick = units.withUnsafeBufferPointer { markdownLineExit($0, entry: entry) }
            let full = scanMarkdownLine(line, entry: entry).exit
            #expect(quick == full, "\(line)")
            entry = full
        }
        #expect(entry == .normal)
    }

    @Test func stateRoundTrips() {
        let states: [MarkdownLineState] = [
            .normal,
            .inFence(MarkdownFence(marker: 0x60, length: 3)),
            .inFence(MarkdownFence(marker: 0x7E, length: 12)),
        ]
        for state in states {
            #expect(MarkdownLineState(rawValue: state.rawValue) == state)
        }
    }

    @Test func multiByteTextKeepsOffsets() {
        let line = "🎉 **party** é"
        #expect(text(line, with: .strong) == "**party**")
    }
}
