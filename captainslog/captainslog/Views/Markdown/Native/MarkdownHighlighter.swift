import AppKit
import CaptainsLogKit

// Keeps a text storage styled as markdown while it is edited.
//
// Each edit restyles only the lines it touched. Every line carries the scanner state it was
// styled with (`markdownLineState`), so after the touched lines the restyle carries on only while
// the state it arrives with differs from the one stored, which only happens when a code fence
// opens or closes. Styling never changes characters, so the storage's string is always the exact
// markdown source.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate, NSLayoutManagerDelegate {
    private let theme = MarkdownTheme.shared
    private var scratch: [UInt16] = []

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        restyle(textStorage, editedRange: editedRange)
    }

    func restyle(_ storage: NSTextStorage, editedRange: NSRange) {
        let string = storage.mutableString
        let length = string.length
        guard length > 0 else { return }

        let lower = min(editedRange.location, length)
        let upper = min(NSMaxRange(editedRange), length)
        var lineStart = string.paragraphRange(for: NSRange(location: lower, length: 0)).location
        // Through the line holding the unit after the edit: an inserted newline ends the edited
        // range, and the text after it is a line of its own with new content.
        let dirtyEnd = NSMaxRange(string.paragraphRange(for: NSRange(location: upper, length: 0)))
        var state = entryState(storage, string, lineStart: lineStart)

        while lineStart < length {
            if lineStart >= dirtyEnd, storedState(storage, at: lineStart) == state.rawValue { break }
            let line = string.paragraphRange(for: NSRange(location: lineStart, length: 0))
            state = styleLine(storage, string, line, entry: state)
            lineStart = NSMaxRange(line)
        }
    }

    // MARK: Line state

    private func storedState(_ storage: NSTextStorage, at location: Int) -> Int? {
        storage.attribute(.markdownLineState, at: location, effectiveRange: nil) as? Int
    }

    /// The state the line at `lineStart` begins in, from the line before it.
    private func entryState(_ storage: NSTextStorage, _ string: NSString, lineStart: Int) -> MarkdownLineState {
        guard lineStart > 0 else { return .normal }
        let previous = string.paragraphRange(for: NSRange(location: lineStart - 1, length: 0))
        guard let stored = storedState(storage, at: previous.location) else {
            // Only an unstyled storage lacks the attribute; walk the fences from the top.
            var state = MarkdownLineState.normal
            var location = 0
            while location < lineStart {
                let line = string.paragraphRange(for: NSRange(location: location, length: 0))
                state = exit(of: line, in: string, entry: state)
                location = NSMaxRange(line)
            }
            return state
        }
        return exit(of: previous, in: string, entry: MarkdownLineState(rawValue: stored))
    }

    private func exit(of line: NSRange, in string: NSString, entry: MarkdownLineState) -> MarkdownLineState {
        let length = Self.contentLength(of: line, in: string)
        return withLine(line.location, length, in: string) { markdownLineExit($0, entry: entry) }
    }

    /// The line's length without its terminator.
    private static func contentLength(of line: NSRange, in string: NSString) -> Int {
        var length = line.length
        while length > 0 {
            let unit = string.character(at: line.location + length - 1)
            guard unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029 else { break }
            length -= 1
        }
        return length
    }

    private func withLine<T>(_ location: Int, _ length: Int, in string: NSString, _ body: (UnsafeBufferPointer<UInt16>) -> T) -> T {
        if scratch.count < length {
            scratch = [UInt16](repeating: 0, count: max(length, scratch.count * 2, 256))
        }
        return scratch.withUnsafeMutableBufferPointer { buffer in
            if length > 0 {
                string.getCharacters(buffer.baseAddress!, range: NSRange(location: location, length: length))
            }
            return body(UnsafeBufferPointer(rebasing: buffer[0..<length]))
        }
    }

    // MARK: Styling a line

    private func styleLine(_ storage: NSTextStorage, _ string: NSString, _ line: NSRange, entry: MarkdownLineState) -> MarkdownLineState {
        let contentLength = Self.contentLength(of: line, in: string)
        let (scan, prefix, indentSpaces) = withLine(line.location, contentLength, in: string) { units in
            let scan = scanMarkdownLine(units, entry: entry)
            return (scan, displayedPrefix(units, scan), Self.indentSpaces(units, scan))
        }
        let location = line.location
        func range(_ units: Range<Int>) -> NSRange {
            NSRange(location: location + units.lowerBound, length: units.count)
        }

        let role: MarkdownTheme.FontRole
        let kind: MarkdownTheme.ParagraphKind
        switch scan.block {
        case .code, .fenceOpen, .fenceClose:
            role = .code
            kind = .code
        case let .heading(level):
            role = .heading(level)
            kind = .heading(level)
        default:
            role = .body
            kind = .body
        }
        let task = scan.list?.task
        let isChecked = task?.isChecked == true
        let tone = isChecked || !scan.quoteMarkers.isEmpty ? theme.secondary : theme.text
        var headIndent: CGFloat = 0
        if case .body = kind, let prefix {
            var kern = task != nil ? theme.taskKern : 0
            kern += CGFloat(indentSpaces.count) * theme.indentKern
            headIndent = theme.prefixWidth(prefix, extraKern: kern)
        }

        var base: [NSAttributedString.Key: Any] = [
            .font: theme.font(role),
            .foregroundColor: tone,
            .paragraphStyle: theme.paragraphStyle(kind, headIndent: headIndent),
            .markdownLineState: entry.rawValue,
        ]
        if role == .code { base[.markdownCodeBlock] = true }
        if scan.block == .rule {
            base[.markdownRule] = true
            base[.foregroundColor] = NSColor.clear
        }
        storage.setAttributes(base, range: line)
        guard scan.block != .rule, scan.block != .code else { return scan.exit }

        if isChecked, scan.contentStart < contentLength {
            storage.addAttributes(
                [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: theme.secondary],
                range: range(scan.contentStart..<contentLength)
            )
        }
        for run in scan.runs {
            storage.addAttributes(runAttributes(run.style, role: role), range: range(run.range))
        }
        for marker in scan.quoteMarkers {
            storage.addAttributes([.markdownQuote: true, .foregroundColor: NSColor.clear], range: range(marker..<(marker + 1)))
        }
        if let list = scan.list {
            if !indentSpaces.isEmpty {
                storage.addAttribute(.kern, value: theme.indentKern, range: range(indentSpaces))
            }
            if let task {
                if list.kind == .bullet {
                    storage.addAttribute(.markdownHidden, value: true, range: range(list.range))
                }
                storage.addAttributes(
                    [.markdownTask: task.isChecked, .foregroundColor: NSColor.clear, .cursor: NSCursor.pointingHand],
                    range: range(task.range)
                )
                // `[x]` is wider than `[ ]`; kern the mark so checked text does not shift.
                let mark = task.range.lowerBound + 1
                let markKern = theme.advance(of: " ") - theme.advance(of: task.isChecked ? "x" : " ")
                storage.addAttribute(.kern, value: markKern, range: range(mark..<(mark + 1)))
                storage.addAttribute(.kern, value: theme.taskKern, range: range((task.range.upperBound - 1)..<task.range.upperBound))
            } else {
                storage.addAttribute(.foregroundColor, value: theme.secondary, range: range(list.range))
            }
        }
        for link in scan.links where !link.destination.isEmpty {
            storage.addAttribute(.markdownLink, value: link.destination, range: range(link.range))
        }
        return scan.exit
    }

    private func runAttributes(_ style: MarkdownInlineStyle, role: MarkdownTheme.FontRole) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if !style.isDisjoint(with: [.strong, .emphasis, .code]) {
            attributes[.font] = theme.font(role, style)
        }
        if style.contains(.syntax) {
            attributes[.foregroundColor] = theme.syntax
        } else if style.contains(.link) {
            attributes[.foregroundColor] = theme.link
        } else if style.contains(.strikethrough) {
            attributes[.foregroundColor] = theme.secondary
        }
        if style.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if style.contains(.code) {
            attributes[.markdownInlineCode] = true
        }
        return attributes
    }

    /// The spaces before a list marker, after any quote prefix.
    private static func indentSpaces(_ units: UnsafeBufferPointer<UInt16>, _ scan: MarkdownLineScan) -> Range<Int> {
        guard let list = scan.list else { return 0..<0 }
        // A quote's `>` takes one space with it.
        var floor = 0
        if let last = scan.quoteMarkers.last {
            floor = last + 1
            if floor < units.count, units[floor] == 0x20 || units[floor] == 0x09 { floor += 1 }
        }
        var start = list.range.lowerBound
        while start > floor, units[start - 1] == 0x20 { start -= 1 }
        return start..<list.range.lowerBound
    }

    /// The line's prefix up to its content as it will be laid out, for measuring the hanging
    /// indent: a task's hidden `- ` takes no space. Nil when there is no prefix.
    private func displayedPrefix(_ units: UnsafeBufferPointer<UInt16>, _ scan: MarkdownLineScan) -> String? {
        guard scan.contentStart > 0 else { return nil }
        var display: [UInt16] = []
        display.reserveCapacity(scan.contentStart)
        for index in 0..<scan.contentStart {
            if let list = scan.list, list.kind == .bullet, list.task != nil, list.range.contains(index) { continue }
            // The mark is kerned to the width of a space.
            if let task = scan.list?.task, index == task.range.lowerBound + 1 {
                display.append(0x20)
                continue
            }
            display.append(units[index])
        }
        return String(decoding: display, as: UTF16.self)
    }

    // MARK: Glyphs

    /// Hides a task's `- `: the characters stay, so the markdown is unchanged, but they lay out
    /// as zero-width control glyphs and draw nothing.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage, glyphRange.length > 0 else { return 0 }
        let count = glyphRange.length
        let first = characterIndexes[0]
        let last = characterIndexes[count - 1]
        guard last >= first else { return 0 }

        var found = false
        storage.enumerateAttribute(
            .markdownHidden,
            in: NSRange(location: first, length: last - first + 1),
            options: .longestEffectiveRangeNotRequired
        ) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        guard found else { return 0 }

        var newProperties = Array(UnsafeBufferPointer(start: properties, count: count))
        for index in 0..<count where storage.attribute(.markdownHidden, at: characterIndexes[index], effectiveRange: nil) != nil {
            newProperties[index] = .controlCharacter
        }
        layoutManager.setGlyphs(
            glyphs, properties: newProperties, characterIndexes: characterIndexes,
            font: font, forGlyphRange: glyphRange
        )
        return count
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        if layoutManager.textStorage?.attribute(.markdownHidden, at: charIndex, effectiveRange: nil) != nil {
            return .zeroAdvancement
        }
        return action
    }
}
