import Foundation
import Testing
import CaptainsLogKit

// Pure logic (no SwiftData), so no shared container needed and parallel execution is fine.
struct MarkdownSpanTests {
    private func spans(_ source: String) -> [(String, MarkdownSpanKind)] {
        markdownSpans(in: source).map { (String(source[$0.range]), $0.kind) }
    }

    @Test func emptyStringHasNoSpans() {
        #expect(markdownSpans(in: "").isEmpty)
        #expect(markdownSpans(in: "plain text, nothing to style").isEmpty)
    }

    @Test func strongCoversDelimiters() {
        let result = spans("**bold**")
        #expect(result.contains { $0 == ("**bold**", .strong) })
    }

    @Test func emphasisCoversDelimiters() {
        let result = spans("_italic_")
        #expect(result.contains { $0 == ("_italic_", .emphasis) })
    }

    @Test func strongInTheMiddleOfALine() {
        let result = spans("met with **Alice** today")
        #expect(result.contains { $0 == ("**Alice**", .strong) })
    }

    @Test func nestedEmphasisInsideStrong() {
        let result = spans("**_x_**")
        #expect(result.contains { $0 == ("**_x_**", .strong) })
        #expect(result.contains { $0 == ("_x_", .emphasis) })
    }

    @Test func strikethrough() {
        let result = spans("~~gone~~")
        #expect(result.contains { $0 == ("~~gone~~", .strikethrough) })
    }

    @Test func inlineCode() {
        let result = spans("run `just test` now")
        #expect(result.contains { $0 == ("`just test`", .inlineCode) })
    }

    @Test func heading() {
        let result = markdownSpans(in: "## Key")
        #expect(result.contains { $0.kind == .heading(2) })
    }

    @Test func link() {
        let result = markdownSpans(in: "see [docs](https://example.com)")
        let linkSpan = result.first { if case .link = $0.kind { return true } else { return false } }
        #expect(linkSpan != nil)
        if case let .link(url)? = linkSpan?.kind {
            #expect(url == URL(string: "https://example.com"))
        }
    }

    @Test func unorderedListMarker() {
        let result = spans("- first\n- second")
        let markers = result.filter { $0.1 == .listItemMarker }
        #expect(markers.count == 2)
        #expect(markers.allSatisfy { $0.0 == "- " })
    }

    @Test func orderedListMarker() {
        let result = spans("1. first\n2. second")
        let markers = result.filter { $0.1 == .listItemMarker }
        #expect(markers.contains { $0.0 == "1. " })
        #expect(markers.contains { $0.0 == "2. " })
    }

    @Test func multiByteOffsetsStayAligned() {
        // A leading emoji (4 UTF-8 bytes) must not shift the span onto the wrong characters.
        let result = spans("🎉 **party**")
        #expect(result.contains { $0 == ("**party**", .strong) })
    }

    @Test func emphasisWithAccentedContent() {
        let result = spans("_café_")
        #expect(result.contains { $0 == ("_café_", .emphasis) })
    }

    @Test func scorecardThemeLineIsNotMutatedByParsing() {
        // InterviewDetailView stores themes as "- _Theme_" and matches on that literal source.
        let theme = "- _Reasons from first principles_"
        #expect(markdownSpans(in: theme).allSatisfy { theme.indices.contains($0.range.lowerBound) })
    }
}

// Slack -> markdown, the paste direction. The copy direction is `SlackHTMLTests` below.
struct SlackPasteTests {
    /// The real `org.chromium.web-custom-data` payload from copying a Slack message with a bold
    /// line, a bulleted list, a labelled link, and a blockquote of bold+italic+strike. Captured
    /// with `just pbdump`; kept verbatim so a format change in Slack fails loudly here.
    private static let realSlackPayload = Data(base64Encoded: "ZAUAAAIAAAALAAAAcwBsAGEAYwBrAC8AdABlAHgAdAB5AAAA9wEAAHsAIgBvAHAAcwAiADoAWwB7ACIAaQBuAHMAZQByAHQAIgA6ACIASABlAGEAZABpAG4AZwAgAGUAZABpAHQAaQBuAGcAIAB3AG8AcgBrAHMAIgAsACIAYQB0AHQAcgBpAGIAdQB0AGUAcwAiADoAewAiAGIAbwBsAGQAIgA6AHQAcgB1AGUAfQB9ACwAewAiAGkAbgBzAGUAcgB0ACIAOgAiAFwAbgAiAH0ALAB7ACIAaQBuAHMAZQByAHQAIgA6ACIARgBpAHIAcwB0ACAAYgB1AGwAbABlAHQAIABwAG8AaQBuAHQALgAgACIALAAiAGEAdAB0AHIAaQBiAHUAdABlAHMAIgA6AHsAIgBiAG8AbABkACIAOgB0AHIAdQBlAH0AfQAsAHsAIgBpAG4AcwBlAHIAdAAiADoAIgBsAGkAbgBrACIALAAiAGEAdAB0AHIAaQBiAHUAdABlAHMAIgA6AHsAIgBsAGkAbgBrACIAOgAiAGgAdAB0AHAAcwA6AC8ALwBnAG8AbwBnAGwAZQAuAGMAbwBtACIAfQB9ACwAewAiAGkAbgBzAGUAcgB0ACIAOgAiAFwAbgAiACwAIgBhAHQAdAByAGkAYgB1AHQAZQBzACIAOgB7ACIAbABpAHMAdAAiADoAIgBiAHUAbABsAGUAdAAiAH0AfQAsAHsAIgBpAG4AcwBlAHIAdAAiADoAIgBTAGUAYwBvAG4AZAAgAGIAdQBsAGwAZQB0ACAAcABvAGkAbgB0ACIAfQAsAHsAIgBpAG4AcwBlAHIAdAAiADoAIgBcAG4AIgAsACIAYQB0AHQAcgBpAGIAdQB0AGUAcwAiADoAewAiAGwAaQBzAHQAIgA6ACIAYgB1AGwAbABlAHQAIgB9AH0ALAB7ACIAaQBuAHMAZQByAHQAIgA6ACIAdABoAGUAIAByAGEAYwBlACAAaQBzACAAbgBvAHQAIABhAGwAdwBhAHkAcwAgAHQAbwAgAHQAaABlACAAIgB9ACwAewAiAGkAbgBzAGUAcgB0ACIAOgAiAHMAdwBpAGYAdAAiACwAIgBhAHQAdAByAGkAYgB1AHQAZQBzACIAOgB7ACIAYgBvAGwAZAAiADoAdAByAHUAZQAsACIAaQB0AGEAbABpAGMAIgA6AHQAcgB1AGUALAAiAHMAdAByAGkAawBlACIAOgB0AHIAdQBlAH0AfQAsAHsAIgBpAG4AcwBlAHIAdAAiADoAIgBcAG4AIgAsACIAYQB0AHQAcgBpAGIAdQB0AGUAcwAiADoAewAiAGIAbABvAGMAawBxAHUAbwB0AGUAIgA6AHQAcgB1AGUAfQB9AF0AfQAAAA0AAAB0AGUAeAB0AC8AbQBhAHIAawBkAG8AdwBuAAAAlgAAACoAKgBIAGUAYQBkAGkAbgBnACAAZQBkAGkAdABpAG4AZwAgAHcAbwByAGsAcwAqACoACgAKAC0AIAAqACoARgBpAHIAcwB0ACAAYgB1AGwAbABlAHQAIABwAG8AaQBuAHQALgAgACoAKgBbAGwAaQBuAGsAXQAoAGgAdAB0AHAAcwA6AC8ALwBnAG8AbwBnAGwAZQAuAGMAbwBtACkACgAtACAAUwBlAGMAbwBuAGQAIABiAHUAbABsAGUAdAAgAHAAbwBpAG4AdAAKAAoAPgAgAHQAaABlACAAcgBhAGMAZQAgAGkAcwAgAG4AbwB0ACAAYQBsAHcAYQB5AHMAIAB0AG8AIAB0AGgAZQAgACoAKgAqAH4AfgBzAHcAaQBmAHQAfgB+ACoAKgAqAA==")!

    /// Encode a MIME map the way Chromium's `Pickle` does, to exercise the decoder's shape.
    private func encode(_ entries: [(String, String)]) -> Data {
        var payload = Data()
        func appendUInt32(_ value: UInt32) {
            payload.append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
                                        UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
        }
        func appendString(_ string: String) {
            let units = Array(string.utf16)
            appendUInt32(UInt32(units.count))
            for unit in units { payload.append(contentsOf: [UInt8(unit & 0xFF), UInt8(unit >> 8)]) }
            payload.append(contentsOf: [UInt8](repeating: 0, count: (4 - payload.count % 4) % 4))
        }
        appendUInt32(UInt32(entries.count))
        for (key, value) in entries { appendString(key); appendString(value) }

        var data = Data()
        let size = UInt32(payload.count)
        data.append(contentsOf: [UInt8(size & 0xFF), UInt8((size >> 8) & 0xFF),
                                 UInt8((size >> 16) & 0xFF), UInt8((size >> 24) & 0xFF)])
        data.append(payload)
        return data
    }

    // MARK: container decoding

    @Test func decodesRealSlackPayload() {
        let entries = decodeWebCustomData(Self.realSlackPayload)
        #expect(entries.count == 2)
        #expect(entries["slack/texty"]?.hasPrefix(#"{"ops":["#) == true)
        #expect(entries["text/markdown"] == """
        **Heading editing works**

        - **First bullet point. **[link](https://google.com)
        - Second bullet point

        > the race is not always to the ***~~swift~~***
        """)
    }

    @Test func decodesRoundTrippedEntries() {
        let data = encode([("text/markdown", "**hi**"), ("slack/texty", "{}")])
        #expect(decodeWebCustomData(data) == ["text/markdown": "**hi**", "slack/texty": "{}"])
    }

    @Test func decodesMultiByteContent() {
        // Emoji are surrogate pairs in UTF-16, so the stored count is code units, not characters.
        let entries = decodeWebCustomData(encode([("text/markdown", "shipped 🎉 café")]))
        #expect(entries["text/markdown"] == "shipped 🎉 café")
    }

    @Test func malformedPayloadsDecodeToNothing() {
        #expect(decodeWebCustomData(Data()).isEmpty)
        #expect(decodeWebCustomData(Data([0x01, 0x02])).isEmpty)
        // A string length far beyond the buffer: refuse it rather than reading out of bounds.
        #expect(decodeWebCustomData(Data([0x08, 0, 0, 0, 0x01, 0, 0, 0, 0xFF, 0, 0, 0])).isEmpty)
    }

    @Test func truncatedPayloadKeepsValidPrefix() {
        var data = encode([("text/markdown", "**hi**"), ("slack/texty", "{}")])
        data.removeLast(8)
        #expect(decodeWebCustomData(data)["text/markdown"] == "**hi**")
    }

    // MARK: the trailing-space wart

    @Test func trailingSpaceMovesOutsideTheDelimiter() {
        #expect(normalizeSlackMarkdown("**bold. **x") == "**bold.** x")
        #expect(normalizeSlackMarkdown("__bold __x") == "__bold__ x")
        #expect(normalizeSlackMarkdown("~~gone ~~x") == "~~gone~~ x")
    }

    @Test func normalizedWartActuallyParsesAsBold() {
        // The point of the repair: before it, cmark finds no spans at all.
        #expect(markdownSpans(in: "**bold. **x").isEmpty)
        #expect(markdownSpans(in: normalizeSlackMarkdown("**bold. **x")).contains { $0.kind == .strong })
    }

    @Test func wellFormedEmphasisIsUntouched() {
        #expect(normalizeSlackMarkdown("met with **Alice** today") == "met with **Alice** today")
        #expect(normalizeSlackMarkdown("***~~swift~~***") == "***~~swift~~***")
    }

    @Test func singleDelimitersAreNeverTouched() {
        // Indistinguishable from prose: repairing these corrupts approximations and arithmetic.
        #expect(normalizeSlackMarkdown("approx ~5 and ~10 items") == "approx ~5 and ~10 items")
        #expect(normalizeSlackMarkdown("2 * 3 and 4 * 5 = 26") == "2 * 3 and 4 * 5 = 26")
        #expect(normalizeSlackMarkdown("cut _from _here") == "cut _from _here")
        // The accepted cost of that rule: Slack's italic-ending-in-a-space stays broken.
        #expect(normalizeSlackMarkdown("*italic *x") == "*italic *x")
    }

    @Test func repairsEveryWartOnALine() {
        #expect(normalizeSlackMarkdown("**a **and **b **c") == "**a** and **b** c")
    }

    // MARK: end to end

    @Test func realPayloadYieldsParseableMarkdown() {
        let markdown = slackMarkdown(fromWebCustomData: Self.realSlackPayload)
        #expect(markdown != nil)
        guard let markdown else { return }

        // The wart on the first bullet is repaired, so its bold now parses.
        #expect(markdown.contains("- **First bullet point.** [link](https://google.com)"))
        let spans = markdownSpans(in: markdown)
        #expect(spans.filter { $0.kind == .strong }.count == 3)
        #expect(spans.contains { $0.kind == .link(URL(string: "https://google.com")) })
        #expect(spans.contains { $0.kind == .strikethrough })
        #expect(spans.filter { $0.kind == .listItemMarker }.count == 2)
    }

    @Test func payloadWithoutMarkdownEntryFallsBack() {
        #expect(slackMarkdown(fromWebCustomData: encode([("slack/texty", "{}")])) == nil)
        #expect(slackMarkdown(fromWebCustomData: Data()) == nil)
    }
}

// Markdown -> Slack, the copy direction. HTML is what Slack's composer parses on paste.
struct SlackHTMLTests {
    @Test func bulletsBecomeARealList() {
        #expect(markdownToSlackHTML("- a\n- b") == "<ul><li>a</li><li>b</li></ul>")
    }

    @Test func numberedListBecomesOrderedList() {
        #expect(markdownToSlackHTML("1. a\n2. b") == "<ol><li>a</li><li>b</li></ol>")
    }

    @Test func nestedListNestsInsideItsItem() {
        #expect(markdownToSlackHTML("- a\n    - b") == "<ul><li>a<ul><li>b</li></ul></li></ul>")
    }

    @Test func emphasisMapsToTags() {
        #expect(markdownToSlackHTML("**b**") == "<p><strong>b</strong></p>")
        #expect(markdownToSlackHTML("_i_") == "<p><em>i</em></p>")
        #expect(markdownToSlackHTML("*i*") == "<p><em>i</em></p>")
        #expect(markdownToSlackHTML("~~gone~~") == "<p><s>gone</s></p>")
    }

    @Test func nestedEmphasisNests() {
        #expect(markdownToSlackHTML("~~the **_swift_**~~") == "<p><s>the <strong><em>swift</em></strong></s></p>")
    }

    @Test func linkKeepsItsLabel() {
        #expect(markdownToSlackHTML("[link](https://google.com)") == #"<p><a href="https://google.com">link</a></p>"#)
    }

    @Test func headingBecomesBoldParagraph() {
        #expect(markdownToSlackHTML("# Title") == "<p><strong>Title</strong></p>")
    }

    @Test func blockQuoteBecomesBlockquote() {
        #expect(markdownToSlackHTML("> quoted") == "<blockquote><p>quoted</p></blockquote>")
    }

    @Test func codeMapsToCodeTags() {
        #expect(markdownToSlackHTML("`x`") == "<p><code>x</code></p>")
        #expect(markdownToSlackHTML("```\nlet x = 1\n```") == "<pre><code>let x = 1</code></pre>")
    }

    @Test func blankLinesBetweenBlocksBecomeEmptyParagraphs() {
        let note = "**Title**\n\n**Section**\n\n- a\n- b\n\n\n**Next**\n- c\n\n```\nx\n```\n\ndone"
        #expect(markdownToSlackHTML(note) == [
            "<p><strong>Title</strong></p>", "<p><br></p>",
            "<p><strong>Section</strong></p>", "<p><br></p>",
            "<ul><li>a</li><li>b</li></ul>", "<p><br></p>",
            "<p><strong>Next</strong></p>",
            "<ul><li>c</li></ul>", "<p><br></p>",
            "<pre><code>x</code></pre>", "<p><br></p>",
            "<p>done</p>",
        ].joined())
    }

    @Test func oneBlankLineAfterAListKeepsItsGap() {
        #expect(markdownToSlackHTML("- a\n\n**Next**") == "<ul><li>a</li></ul><p><br></p><p><strong>Next</strong></p>")
        #expect(markdownToSlackHTML("- a\n  - b\n\nnext") == "<ul><li>a<ul><li>b</li></ul></li></ul><p><br></p><p>next</p>")
    }

    @Test func headingDirectlyAboveTextKeepsNoGap() {
        #expect(markdownToSlackHTML("# Title\nbody") == "<p><strong>Title</strong></p><p>body</p>")
    }

    @Test func softBreakStaysALineBreak() {
        #expect(markdownToSlackHTML("one\ntwo") == "<p>one<br>two</p>")
    }

    @Test func htmlMetacharactersAreEscaped() {
        #expect(markdownToSlackHTML("a < b && c") == "<p>a &lt; b &amp;&amp; c</p>")
        #expect(markdownToSlackHTML("`if a < b`") == "<p><code>if a &lt; b</code></p>")
    }

    @Test func scorecardThemeLineBecomesAnItalicBullet() {
        let theme = "- _Reasons from first principles_"
        #expect(markdownToSlackHTML(theme) == "<ul><li><em>Reasons from first principles</em></li></ul>")
    }
}
