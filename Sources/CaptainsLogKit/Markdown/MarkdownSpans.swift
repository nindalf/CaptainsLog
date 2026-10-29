import Foundation
import Markdown

/// A styled region discovered in a markdown source string. Ranges are inclusive of the
/// delimiter characters (a `.strong` span covers the surrounding `**`), so a renderer can
/// both embolden the span and dim just the markers.
public enum MarkdownSpanKind: Equatable, Sendable {
    case strong
    case emphasis
    case strikethrough
    case inlineCode
    case codeBlock
    case heading(Int)
    case link(URL?)
    case blockquote
    case listItemMarker
}

public struct MarkdownSpan: Equatable, Sendable {
    public let range: Range<String.Index>
    public let kind: MarkdownSpanKind

    public init(range: Range<String.Index>, kind: MarkdownSpanKind) {
        self.range = range
        self.kind = kind
    }
}

/// Parse `source` into typed spans with `String.Index` ranges. Cheap enough to run on every
/// keystroke at note-sized text. Pure Foundation + swift-markdown, no UI dependency.
public func markdownSpans(in source: String) -> [MarkdownSpan] {
    guard !source.isEmpty else { return [] }
    let mapper = LineByteMapper(source: source)
    var collector = SpanCollector(mapper: mapper)
    collector.visit(Markdown.Document(parsing: source))
    var spans = collector.spans
    spans.append(contentsOf: listItemMarkerSpans(in: source))
    return spans
}

// MARK: - Walker

private struct SpanCollector: MarkupWalker {
    let mapper: LineByteMapper
    var spans: [MarkdownSpan] = []

    private mutating func record(_ markup: Markup, kind: MarkdownSpanKind) {
        if let range = mapper.range(for: markup.range) {
            spans.append(MarkdownSpan(range: range, kind: kind))
        }
    }

    mutating func visitStrong(_ strong: Strong) {
        record(strong, kind: .strong)
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        record(emphasis, kind: .emphasis)
        descendInto(emphasis)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        record(strikethrough, kind: .strikethrough)
        descendInto(strikethrough)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        record(inlineCode, kind: .inlineCode)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        record(codeBlock, kind: .codeBlock)
    }

    mutating func visitHeading(_ heading: Heading) {
        record(heading, kind: .heading(heading.level))
        descendInto(heading)
    }

    mutating func visitLink(_ link: Link) {
        record(link, kind: .link(link.destination.flatMap(URL.init(string:))))
        descendInto(link)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        record(blockQuote, kind: .blockquote)
        descendInto(blockQuote)
    }
}

// MARK: - List markers

/// cmark's list-item ranges span the whole item, so detect the leading bullet/number marker
/// with a per-line scan instead. Matches `- `, `* `, `+ `, and `1. ` style markers.
private func listItemMarkerSpans(in source: String) -> [MarkdownSpan] {
    var spans: [MarkdownSpan] = []
    var lineStart = source.startIndex
    while lineStart < source.endIndex {
        let lineEnd = source[lineStart...].firstIndex(of: "\n") ?? source.endIndex
        if let marker = markerRange(in: source, lineStart: lineStart, lineEnd: lineEnd) {
            spans.append(MarkdownSpan(range: marker, kind: .listItemMarker))
        }
        lineStart = lineEnd < source.endIndex ? source.index(after: lineEnd) : source.endIndex
    }
    return spans
}

private func markerRange(in source: String, lineStart: String.Index, lineEnd: String.Index) -> Range<String.Index>? {
    var i = lineStart
    while i < lineEnd, source[i] == " " || source[i] == "\t" { i = source.index(after: i) }
    guard i < lineEnd else { return nil }
    let markerStart = i
    let first = source[i]
    if first == "-" || first == "*" || first == "+" {
        let space = source.index(after: i)
        guard space < lineEnd, source[space] == " " else { return nil }
        return markerStart..<source.index(after: space)
    }
    // Ordered list: one or more digits followed by "." or ")", then a space.
    var digits = i
    while digits < lineEnd, source[digits].isNumber { digits = source.index(after: digits) }
    guard digits > i, digits < lineEnd, source[digits] == "." || source[digits] == ")" else { return nil }
    let space = source.index(after: digits)
    guard space < lineEnd, source[space] == " " else { return nil }
    return markerStart..<source.index(after: space)
}

// MARK: - Source location mapping

/// Maps swift-markdown `SourceLocation`s (1-based line, 1-based UTF-8 byte column) onto
/// `Character`-boundary `String.Index`es in the source.
private struct LineByteMapper {
    private let source: String
    private let lineStartByte: [Int]
    private let utf8Count: Int

    init(source: String) {
        self.source = source
        var starts = [0]
        var count = 0
        for byte in source.utf8 {
            count += 1
            if byte == 0x0A { starts.append(count) }
        }
        self.lineStartByte = starts
        self.utf8Count = count
    }

    func range(for sourceRange: SourceRange?) -> Range<String.Index>? {
        guard let sourceRange,
              let lower = index(for: sourceRange.lowerBound),
              let upper = index(for: sourceRange.upperBound),
              lower < upper else { return nil }
        return lower..<upper
    }

    private func index(for location: SourceLocation) -> String.Index? {
        let line = location.line - 1
        guard line >= 0, line < lineStartByte.count else { return source.endIndex }
        var byteOffset = lineStartByte[line] + (location.column - 1)
        byteOffset = min(max(byteOffset, 0), utf8Count)
        guard var idx = source.utf8.index(source.utf8.startIndex, offsetBy: byteOffset, limitedBy: source.utf8.endIndex) else {
            return source.endIndex
        }
        // Snap to the nearest Character boundary at or before the byte offset (defensive:
        // only matters if a column lands inside a multi-byte grapheme, which delimiters never do).
        while idx > source.startIndex, idx.samePosition(in: source) == nil {
            idx = source.utf8.index(before: idx)
        }
        return idx.samePosition(in: source) ?? source.startIndex
    }
}
