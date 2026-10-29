import Foundation

// Line-at-a-time markdown scanner behind the native editor's live styling.
//
// It works on UTF-16 code units, the index space of NSString and NSTextStorage, so the editor can
// restyle just the lines an edit touched without converting offsets. Every markdown delimiter is
// ASCII, so scanning code units is exact. The only state that crosses a line boundary is an open
// fenced code block; everything else is decided by the line alone, which is what lets an
// incremental restyle stop as soon as the state after an edit matches the state before it.
//
// Inline spans do not cross lines: `**bold\nstill bold**` styles neither line. Setext headings,
// indented code blocks and reference links are not recognised.

/// An open fenced code block: the fence character and how many of them opened it.
public struct MarkdownFence: Hashable, Sendable {
    public let marker: UInt16
    public let length: Int

    public init(marker: UInt16, length: Int) {
        self.marker = marker
        self.length = length
    }
}

/// What carries from one line to the next.
public enum MarkdownLineState: Hashable, Sendable {
    case normal
    case inFence(MarkdownFence)

    /// Packs the state into an `Int`, so the editor can store it as a text attribute.
    public var rawValue: Int {
        switch self {
        case .normal: 0
        case let .inFence(fence): (fence.length << 8) | Int(fence.marker & 0xFF)
        }
    }

    public init(rawValue: Int) {
        if rawValue == 0 {
            self = .normal
        } else {
            self = .inFence(MarkdownFence(marker: UInt16(rawValue & 0xFF), length: rawValue >> 8))
        }
    }
}

public enum MarkdownBlock: Equatable, Sendable {
    case paragraph
    case blank
    case heading(level: Int)
    case rule
    case fenceOpen
    case fenceClose
    /// A line inside a fenced code block.
    case code
}

public struct MarkdownTask: Equatable, Sendable {
    /// The three units of `[ ]` or `[x]`.
    public let range: Range<Int>
    public let isChecked: Bool
}

public struct MarkdownListMarker: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case bullet
        case ordered(number: Int, delimiter: UInt16)
    }

    public let kind: Kind
    /// The marker and the one space after it: `- ` or `12. `.
    public let range: Range<Int>
    /// Columns of whitespace before the marker, after any quote prefix.
    public let indent: Int
    public let task: MarkdownTask?
}

public struct MarkdownInlineStyle: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let strong = MarkdownInlineStyle(rawValue: 1 << 0)
    public static let emphasis = MarkdownInlineStyle(rawValue: 1 << 1)
    public static let strikethrough = MarkdownInlineStyle(rawValue: 1 << 2)
    public static let code = MarkdownInlineStyle(rawValue: 1 << 3)
    /// Link text, or a bare URL.
    public static let link = MarkdownInlineStyle(rawValue: 1 << 4)
    /// Delimiters and markers: `**`, a heading's `#`s, a link's `](url)`. Drawn dimmed.
    public static let syntax = MarkdownInlineStyle(rawValue: 1 << 5)
}

public struct MarkdownRun: Equatable, Sendable {
    public let range: Range<Int>
    public let style: MarkdownInlineStyle
}

public struct MarkdownLink: Equatable, Sendable {
    /// The whole construct, brackets and destination included.
    public let range: Range<Int>
    public let destination: String
}

public struct MarkdownLineScan: Equatable, Sendable {
    public var block: MarkdownBlock = .paragraph
    /// Offsets of each `>` of a blockquote prefix.
    public var quoteMarkers: [Int] = []
    public var list: MarkdownListMarker?
    /// Where the line's text starts after its quote, list and task prefixes. Wrapped lines hang here.
    public var contentStart = 0
    /// Styled stretches in order, not overlapping. Unstyled text has no run.
    public var runs: [MarkdownRun] = []
    public var links: [MarkdownLink] = []
    public var exit: MarkdownLineState = .normal
}

/// Scan one line, without its terminator, given the state the previous line left.
public func scanMarkdownLine(_ line: UnsafeBufferPointer<UInt16>, entry: MarkdownLineState) -> MarkdownLineScan {
    var scanner = LineScanner(line: line)
    return scanner.scan(entry: entry)
}

/// Convenience for tests and callers holding a `String`.
public func scanMarkdownLine(_ line: String, entry: MarkdownLineState = .normal) -> MarkdownLineScan {
    let units = Array(line.utf16)
    return units.withUnsafeBufferPointer { scanMarkdownLine($0, entry: entry) }
}

/// The state after `line`, without styling it. Cheap: only fence lines change state.
public func markdownLineExit(_ line: UnsafeBufferPointer<UInt16>, entry: MarkdownLineState) -> MarkdownLineState {
    switch entry {
    case let .inFence(fence):
        return isClosingFence(line, fence) ? .normal : entry
    case .normal:
        let start = skipSpaces(line, from: 0)
        if let fence = openingFence(line, at: start) { return .inFence(fence) }
        return .normal
    }
}

// MARK: - Code units

private enum Code {
    static let tab: UInt16 = 0x09
    static let space: UInt16 = 0x20
    static let bang: UInt16 = 0x21
    static let hash: UInt16 = 0x23
    static let lparen: UInt16 = 0x28
    static let rparen: UInt16 = 0x29
    static let star: UInt16 = 0x2A
    static let plus: UInt16 = 0x2B
    static let dash: UInt16 = 0x2D
    static let dot: UInt16 = 0x2E
    static let colon: UInt16 = 0x3A
    static let lt: UInt16 = 0x3C
    static let gt: UInt16 = 0x3E
    static let lbracket: UInt16 = 0x5B
    static let backslash: UInt16 = 0x5C
    static let rbracket: UInt16 = 0x5D
    static let underscore: UInt16 = 0x5F
    static let backtick: UInt16 = 0x60
    static let tilde: UInt16 = 0x7E
    static let lowerX: UInt16 = 0x78
    static let upperX: UInt16 = 0x58
}

private func isSpaceOrTab(_ unit: UInt16) -> Bool {
    unit == Code.space || unit == Code.tab
}

private func isDigit(_ unit: UInt16) -> Bool {
    unit >= 0x30 && unit <= 0x39
}

private func isASCIIPunctuation(_ unit: UInt16) -> Bool {
    (unit >= 0x21 && unit <= 0x2F) || (unit >= 0x3A && unit <= 0x40)
        || (unit >= 0x5B && unit <= 0x60) || (unit >= 0x7B && unit <= 0x7E)
}

/// Unicode whitespace as CommonMark's flanking rules see it.
private func isWhitespace(_ unit: UInt16) -> Bool {
    switch unit {
    case 0x09, 0x0A, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
        true
    default:
        false
    }
}

/// Unicode punctuation and symbols, which CommonMark treats alike for flanking. Surrogate halves
/// count as neither: the scalar is not known from one unit, and treating it as a letter is safe.
private func isPunctuation(_ unit: UInt16) -> Bool {
    if unit < 0x80 { return isASCIIPunctuation(unit) }
    guard let scalar = Unicode.Scalar(unit) else { return false }
    switch scalar.properties.generalCategory {
    case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
         .initialPunctuation, .finalPunctuation, .otherPunctuation,
         .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
        return true
    default:
        return false
    }
}

private func skipSpaces(_ line: UnsafeBufferPointer<UInt16>, from start: Int) -> Int {
    var i = start
    while i < line.count, isSpaceOrTab(line[i]) { i += 1 }
    return i
}

private func openingFence(_ line: UnsafeBufferPointer<UInt16>, at start: Int) -> MarkdownFence? {
    guard start < line.count else { return nil }
    let marker = line[start]
    guard marker == Code.backtick || marker == Code.tilde else { return nil }
    var i = start
    while i < line.count, line[i] == marker { i += 1 }
    let length = i - start
    guard length >= 3 else { return nil }
    // A backtick fence's info string may not contain a backtick, or "```x```" would open a block.
    if marker == Code.backtick {
        while i < line.count {
            if line[i] == Code.backtick { return nil }
            i += 1
        }
    }
    return MarkdownFence(marker: marker, length: length)
}

private func isClosingFence(_ line: UnsafeBufferPointer<UInt16>, _ fence: MarkdownFence) -> Bool {
    var i = skipSpaces(line, from: 0)
    let start = i
    while i < line.count, line[i] == fence.marker { i += 1 }
    guard i - start >= fence.length else { return false }
    return skipSpaces(line, from: i) == line.count
}

// MARK: - Block structure

private struct LineScanner {
    let line: UnsafeBufferPointer<UInt16>
    var styles: [MarkdownInlineStyle]
    var result = MarkdownLineScan()

    init(line: UnsafeBufferPointer<UInt16>) {
        self.line = line
        self.styles = Array(repeating: [], count: line.count)
    }

    mutating func scan(entry: MarkdownLineState) -> MarkdownLineScan {
        let n = line.count
        result.exit = entry

        if case let .inFence(fence) = entry {
            if isClosingFence(line, fence) {
                result.block = .fenceClose
                result.exit = .normal
                mark(0..<n, .syntax)
            } else {
                result.block = .code
            }
            return finish()
        }

        var i = skipSpaces(line, from: 0)
        if i == n {
            result.block = .blank
            return finish()
        }

        // Blockquote prefixes, nested as `> > text`.
        while i < n, line[i] == Code.gt {
            result.quoteMarkers.append(i)
            i += 1
            if i < n, isSpaceOrTab(line[i]) { i += 1 }
            let next = skipSpaces(line, from: i)
            if next < n, line[next] == Code.gt { i = next } else { break }
        }
        result.contentStart = i

        if result.quoteMarkers.isEmpty, let fence = openingFence(line, at: i) {
            result.block = .fenceOpen
            result.exit = .inFence(fence)
            mark(0..<n, .syntax)
            return finish()
        }

        let indentStart = result.quoteMarkers.isEmpty ? 0 : i
        i = skipSpaces(line, from: i)
        guard i < n else { return finish() }

        if let level = headingLevel(at: i) {
            result.block = .heading(level: level)
            scanHeading(at: i, level: level)
            return finish()
        }
        if isRule(from: i) {
            result.block = .rule
            mark(i..<n, .syntax)
            return finish()
        }
        if let marker = listMarker(at: i, indent: columns(indentStart..<i)) {
            result.list = marker
            result.contentStart = marker.task.map { min($0.range.upperBound + 1, n) } ?? marker.range.upperBound
            if case .ordered = marker.kind { mark(marker.range, .syntax) }
            parseInline(result.contentStart..<n)
            return finish()
        }

        // Indented paragraph text hangs at its own indent.
        result.contentStart = i
        parseInline(i..<n)
        return finish()
    }

    private mutating func finish() -> MarkdownLineScan {
        var runs: [MarkdownRun] = []
        var start = 0
        while start < styles.count {
            let style = styles[start]
            var end = start + 1
            while end < styles.count, styles[end] == style { end += 1 }
            if !style.isEmpty { runs.append(MarkdownRun(range: start..<end, style: style)) }
            start = end
        }
        result.runs = runs
        return result
    }

    private mutating func mark(_ range: Range<Int>, _ style: MarkdownInlineStyle) {
        for i in range { styles[i].formUnion(style) }
    }

    private func columns(_ range: Range<Int>) -> Int {
        range.reduce(0) { $0 + (line[$1] == Code.tab ? 4 : 1) }
    }

    // MARK: Headings and rules

    private func headingLevel(at start: Int) -> Int? {
        var i = start
        while i < line.count, line[i] == Code.hash { i += 1 }
        let level = i - start
        guard (1...6).contains(level) else { return nil }
        guard i == line.count || isSpaceOrTab(line[i]) else { return nil }
        return level
    }

    private mutating func scanHeading(at start: Int, level: Int) {
        let n = line.count
        let contentStart = skipSpaces(line, from: start + level)
        mark(start..<contentStart, .syntax)

        // An optional closing run of `#`s, which must follow a space.
        var end = n
        while end > contentStart, isSpaceOrTab(line[end - 1]) { end -= 1 }
        var hashes = end
        while hashes > contentStart, line[hashes - 1] == Code.hash { hashes -= 1 }
        if hashes < end, hashes == contentStart || isSpaceOrTab(line[hashes - 1]) {
            mark(hashes..<end, .syntax)
            end = hashes
        }
        parseInline(contentStart..<end)
    }

    /// Only dashes make a rule; `***` and `___` stay as text.
    private func isRule(from start: Int) -> Bool {
        guard line[start] == Code.dash else { return false }
        var count = 0
        for i in start..<line.count {
            if line[i] == Code.dash {
                count += 1
            } else if !isSpaceOrTab(line[i]) {
                return false
            }
        }
        return count >= 3
    }

    // MARK: Lists

    private func listMarker(at start: Int, indent: Int) -> MarkdownListMarker? {
        let n = line.count
        let first = line[start]
        var kind: MarkdownListMarker.Kind
        var end: Int

        if first == Code.dash || first == Code.star || first == Code.plus {
            kind = .bullet
            end = start + 1
        } else {
            var i = start
            var number = 0
            while i < n, isDigit(line[i]), i - start < 9 {
                number = number * 10 + Int(line[i] - 0x30)
                i += 1
            }
            guard i > start, i < n, line[i] == Code.dot || line[i] == Code.rparen else { return nil }
            kind = .ordered(number: number, delimiter: line[i])
            end = i + 1
        }
        // The marker needs a space after it, or to end the line (an item still being typed).
        if end < n {
            guard isSpaceOrTab(line[end]) else { return nil }
            end += 1
        }

        var task: MarkdownTask?
        if end + 2 < n, line[end] == Code.lbracket, line[end + 2] == Code.rbracket,
           end + 3 == n || isSpaceOrTab(line[end + 3]) {
            let mark = line[end + 1]
            if mark == Code.space || mark == Code.lowerX || mark == Code.upperX {
                task = MarkdownTask(range: end..<(end + 3), isChecked: mark != Code.space)
            }
        }
        return MarkdownListMarker(kind: kind, range: start..<end, indent: indent, task: task)
    }

    // MARK: Inline

    /// Code spans and escapes first, since nothing inside a code span is markup. Then links, so
    /// their destinations are masked before bare URLs and emphasis look at them.
    private mutating func parseInline(_ range: Range<Int>) {
        guard !range.isEmpty else { return }
        var masked = [Bool](repeating: false, count: line.count)
        scanCodeSpans(range, masked: &masked)
        scanLinks(range, masked: &masked)
        scanBareURLs(range, masked: &masked)
        scanEmphasis(range, masked: masked)
    }

    private mutating func scanCodeSpans(_ range: Range<Int>, masked: inout [Bool]) {
        var i = range.lowerBound
        while i < range.upperBound {
            let unit = line[i]
            if unit == Code.backslash, i + 1 < range.upperBound, isASCIIPunctuation(line[i + 1]) {
                mark(i..<(i + 1), .syntax)
                masked[i] = true
                masked[i + 1] = true
                i += 2
                continue
            }
            guard unit == Code.backtick else {
                i += 1
                continue
            }
            let open = i
            while i < range.upperBound, line[i] == Code.backtick { i += 1 }
            let width = i - open
            // Find a closing run of exactly the same width.
            var j = i
            var close: Int?
            while j < range.upperBound {
                guard line[j] == Code.backtick else {
                    j += 1
                    continue
                }
                let runStart = j
                while j < range.upperBound, line[j] == Code.backtick { j += 1 }
                if j - runStart == width {
                    close = runStart
                    break
                }
            }
            guard let close else { continue }
            let end = close + width
            mark(open..<end, .code)
            mark(open..<(open + width), .syntax)
            mark(close..<end, .syntax)
            for k in open..<end { masked[k] = true }
            i = end
        }
    }

    private mutating func scanLinks(_ range: Range<Int>, masked: inout [Bool]) {
        var i = range.lowerBound
        while i < range.upperBound {
            guard line[i] == Code.lbracket, !masked[i] else {
                i += 1
                continue
            }
            guard let close = matchingBracket(from: i, in: range, masked: masked),
                  close + 1 < range.upperBound, line[close + 1] == Code.lparen, !masked[close + 1],
                  let destinationEnd = matchingParen(from: close + 1, in: range, masked: masked)
            else {
                i += 1
                continue
            }
            let isImage = i > range.lowerBound && line[i - 1] == Code.bang && !masked[i - 1]
            let start = isImage ? i - 1 : i
            mark(start..<(i + 1), .syntax)
            mark((i + 1)..<close, .link)
            mark(close..<(destinationEnd + 1), .syntax)
            masked[i] = true
            for k in close...destinationEnd { masked[k] = true }
            result.links.append(MarkdownLink(
                range: start..<(destinationEnd + 1),
                destination: linkDestination((close + 2)..<destinationEnd)
            ))
            i = destinationEnd + 1
        }
    }

    private func matchingBracket(from open: Int, in range: Range<Int>, masked: [Bool]) -> Int? {
        var depth = 0
        for i in open..<range.upperBound where !masked[i] {
            if line[i] == Code.lbracket {
                depth += 1
            } else if line[i] == Code.rbracket {
                depth -= 1
                if depth == 0 { return i }
            }
        }
        return nil
    }

    private func matchingParen(from open: Int, in range: Range<Int>, masked: [Bool]) -> Int? {
        var depth = 0
        var i = open
        while i < range.upperBound {
            let unit = line[i]
            if unit == Code.backslash, i + 1 < range.upperBound {
                i += 2
                continue
            }
            if unit == Code.lparen {
                depth += 1
            } else if unit == Code.rparen {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }

    /// The URL part of a link destination: `<...>` unwrapped and any `"title"` dropped.
    private func linkDestination(_ range: Range<Int>) -> String {
        var lower = skipSpaces(line, from: range.lowerBound)
        var upper = range.upperBound
        if lower < upper, line[lower] == Code.lt, let gt = (lower..<upper).first(where: { line[$0] == Code.gt }) {
            lower += 1
            upper = gt
        } else if let space = (lower..<upper).first(where: { isSpaceOrTab(line[$0]) }) {
            upper = space
        }
        guard lower < upper else { return "" }
        return String(decoding: UnsafeBufferPointer(rebasing: line[lower..<upper]), as: UTF16.self)
    }

    /// `<https://...>` autolinks and bare `http(s)://` URLs. Masking a URL keeps the `_` and `*`
    /// common in URLs from opening emphasis.
    private mutating func scanBareURLs(_ range: Range<Int>, masked: inout [Bool]) {
        var i = range.lowerBound
        while i < range.upperBound {
            guard !masked[i], !styles[i].contains(.link), let schemeEnd = schemeEnd(at: i, limit: range.upperBound),
                  i == range.lowerBound || !isURLWordUnit(line[i - 1])
            else {
                i += 1
                continue
            }
            var end = schemeEnd
            while end < range.upperBound, !isWhitespace(line[end]), line[end] != Code.lt, line[end] != Code.gt,
                  !masked[end] {
                end += 1
            }
            end = trimURLTail(i..<end)
            guard end > schemeEnd else {
                i = schemeEnd
                continue
            }
            let isAutolink = i > range.lowerBound && line[i - 1] == Code.lt && end < range.upperBound && line[end] == Code.gt
            if isAutolink {
                mark((i - 1)..<i, .syntax)
                mark(end..<(end + 1), .syntax)
            }
            mark(i..<end, .link)
            for k in i..<end { masked[k] = true }
            let destination = String(decoding: UnsafeBufferPointer(rebasing: line[i..<end]), as: UTF16.self)
            result.links.append(MarkdownLink(range: i..<end, destination: destination))
            i = end
        }
    }

    private func isURLWordUnit(_ unit: UInt16) -> Bool {
        (unit >= 0x30 && unit <= 0x39) || (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)
    }

    /// The index after `http://` or `https://` starting at `start`, if one does. Called at every
    /// unit, so it bails on the first letter.
    private func schemeEnd(at start: Int, limit: Int) -> Int? {
        guard line[start] | 0x20 == 0x68, start + 7 <= limit,
              line[start + 1] | 0x20 == 0x74, line[start + 2] | 0x20 == 0x74, line[start + 3] | 0x20 == 0x70
        else { return nil }
        var i = start + 4
        if line[i] | 0x20 == 0x73 { i += 1 }
        guard i + 3 <= limit, line[i] == Code.colon, line[i + 1] == 0x2F, line[i + 2] == 0x2F else { return nil }
        return i + 3
    }

    /// GFM's autolink trimming: trailing punctuation is not part of the URL, and a closing paren
    /// only belongs to it when balanced, so `(see https://x.com)` keeps its `)` outside.
    private func trimURLTail(_ range: Range<Int>) -> Int {
        var end = range.upperBound
        let trailing: Set<UInt16> = [0x21, 0x22, 0x27, 0x2A, 0x2C, 0x2E, 0x3A, 0x3B, 0x3F, 0x5F, 0x7E]
        while end > range.lowerBound {
            let last = line[end - 1]
            if trailing.contains(last) {
                end -= 1
            } else if last == Code.rparen {
                let opens = (range.lowerBound..<end).filter { line[$0] == Code.lparen }.count
                let closes = (range.lowerBound..<end).filter { line[$0] == Code.rparen }.count
                guard closes > opens else { break }
                end -= 1
            } else {
                break
            }
        }
        return end
    }

    // MARK: Emphasis

    private struct Delimiter {
        let unit: UInt16
        var start: Int
        var count: Int
        let originalCount: Int
        let canOpen: Bool
        let canClose: Bool
    }

    /// CommonMark's delimiter-run algorithm, including the rule of three, plus GFM tildes.
    private mutating func scanEmphasis(_ range: Range<Int>, masked: [Bool]) {
        var delimiters: [Delimiter] = []
        var i = range.lowerBound
        while i < range.upperBound {
            let unit = line[i]
            guard !masked[i], unit == Code.star || unit == Code.underscore || unit == Code.tilde else {
                i += 1
                continue
            }
            let start = i
            while i < range.upperBound, line[i] == unit, !masked[i] { i += 1 }
            let count = i - start
            if unit == Code.tilde, count > 2 { continue }

            let before = start > range.lowerBound ? line[start - 1] : Code.space
            let after = i < range.upperBound ? line[i] : Code.space
            let leftFlanking = !isWhitespace(after)
                && (!isPunctuation(after) || isWhitespace(before) || isPunctuation(before))
            let rightFlanking = !isWhitespace(before)
                && (!isPunctuation(before) || isWhitespace(after) || isPunctuation(after))
            let canOpen: Bool
            let canClose: Bool
            if unit == Code.underscore {
                canOpen = leftFlanking && (!rightFlanking || isPunctuation(before))
                canClose = rightFlanking && (!leftFlanking || isPunctuation(after))
            } else {
                canOpen = leftFlanking
                canClose = rightFlanking
            }
            guard canOpen || canClose else { continue }
            delimiters.append(Delimiter(
                unit: unit, start: start, count: count, originalCount: count,
                canOpen: canOpen, canClose: canClose
            ))
        }

        var closerIndex = 0
        while closerIndex < delimiters.count {
            let closer = delimiters[closerIndex]
            guard closer.canClose, closer.count > 0,
                  let openerIndex = opener(for: closer, before: closerIndex, in: delimiters)
            else {
                closerIndex += 1
                continue
            }
            let opener = delimiters[openerIndex]
            let used: Int
            let style: MarkdownInlineStyle
            if closer.unit == Code.tilde {
                used = closer.count
                style = .strikethrough
            } else {
                used = opener.count >= 2 && closer.count >= 2 ? 2 : 1
                style = used == 2 ? .strong : .emphasis
            }
            let openerUsed = (opener.start + opener.count - used)..<(opener.start + opener.count)
            let closerUsed = closer.start..<(closer.start + used)
            mark(openerUsed.lowerBound..<closerUsed.upperBound, style)
            mark(openerUsed, .syntax)
            mark(closerUsed, .syntax)

            delimiters[openerIndex].count -= used
            delimiters[closerIndex].count -= used
            delimiters[closerIndex].start += used
            // Delimiters between the pair can no longer match anything.
            delimiters.removeSubrange((openerIndex + 1)..<closerIndex)
            closerIndex = openerIndex + 1
            if delimiters[closerIndex].count == 0 { closerIndex += 1 }
        }
    }

    private func opener(for closer: Delimiter, before closerIndex: Int, in delimiters: [Delimiter]) -> Int? {
        var index = closerIndex - 1
        while index >= 0 {
            let candidate = delimiters[index]
            if candidate.unit == closer.unit, candidate.canOpen, candidate.count > 0 {
                if closer.unit == Code.tilde {
                    if candidate.count == closer.count { return index }
                } else {
                    let bothFlanking = candidate.canClose || closer.canOpen
                    let sum = candidate.originalCount + closer.originalCount
                    let ruleOfThree = bothFlanking && sum % 3 == 0
                        && !(candidate.originalCount % 3 == 0 && closer.originalCount % 3 == 0)
                    if !ruleOfThree { return index }
                }
            }
            index -= 1
        }
        return nil
    }
}
