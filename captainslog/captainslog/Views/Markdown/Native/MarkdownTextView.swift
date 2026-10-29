import AppKit
import CaptainsLogKit

// The native editor's text view: TextKit 1, plain text, styled by `MarkdownHighlighter` and drawn
// by `MarkdownLayoutManager`. Adds the markdown editing behaviours: clickable checkboxes, list
// continuation and indenting, formatting shortcuts, and pastes that understand Slack and URLs.
final class MarkdownTextView: NSTextView {
    weak var controller: MarkdownEditorController?
    var placeholder = "" {
        didSet { needsDisplay = true }
    }

    private let theme = MarkdownTheme.shared

    static func make() -> MarkdownTextView {
        let storage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 5
        layoutManager.addTextContainer(container)

        let textView = MarkdownTextView(frame: .zero, textContainer: container)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.usesFontPanel = false
        textView.usesRuler = false
        // Markdown is punctuation-sensitive: `--` must stay two dashes and quotes straight.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.font = MarkdownTheme.shared.body
        textView.typingAttributes = [
            .font: MarkdownTheme.shared.body,
            .foregroundColor: MarkdownTheme.shared.text,
            .paragraphStyle: MarkdownTheme.shared.paragraphStyle(.body),
        ]
        return textView
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !placeholder.isEmpty, textStorage?.length == 0 else { return }
        let origin = NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0), y: textContainerOrigin.y)
        (placeholder as NSString).draw(at: origin, withAttributes: [.font: theme.body, .foregroundColor: theme.placeholder])
    }

    override func didChangeText() {
        super.didChangeText()
        // The placeholder's pixels lie outside what an edit redraws.
        if !placeholder.isEmpty, (textStorage?.length ?? 0) <= 1 { needsDisplay = true }
    }

    /// A field taller than the window scrolls the page around it, not itself, so bring the
    /// range into view there too.
    override func scrollRangeToVisible(_ range: NSRange) {
        super.scrollRangeToVisible(range)
        guard let layoutManager, let textContainer, let scrollView = enclosingScrollView, window != nil else { return }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect: NSRect
        if glyphs.length > 0 {
            rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        } else if glyphs.location < layoutManager.numberOfGlyphs {
            rect = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        } else if !layoutManager.extraLineFragmentRect.isEmpty {
            rect = layoutManager.extraLineFragmentRect
        } else if layoutManager.numberOfGlyphs > 0 {
            rect = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.numberOfGlyphs - 1, effectiveRange: nil)
        } else {
            return
        }
        rect = rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y).insetBy(dx: 0, dy: -6)
        scrollView.scrollToVisible(convert(rect, to: scrollView))
    }

    // MARK: Focus

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { controller?.focusDidChange(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { controller?.focusDidChange(false) }
        return resigned
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let box = taskBox(at: point) {
            toggleTask(boxAt: box)
            return
        }
        if event.modifierFlags.contains(.command), let url = link(at: point) {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    private func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        return min(layoutManager.characterIndexForGlyph(at: glyph), storage.length - 1)
    }

    /// The index of the `[` of the task box under `point`, if there is one.
    private func taskBox(at point: NSPoint) -> Int? {
        guard let index = characterIndex(at: point), let storage = textStorage,
              let layoutManager = layoutManager as? MarkdownLayoutManager else { return nil }
        let line = line(at: index)
        guard let task = line.scan.list?.task else { return nil }
        let box = line.range.location + task.range.lowerBound
        let rect = layoutManager.checkboxRect(forCharacterAt: box, storage: storage)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            .insetBy(dx: -3, dy: -3)
        return rect.contains(point) ? box : nil
    }

    private func link(at point: NSPoint) -> URL? {
        guard let index = characterIndex(at: point),
              let destination = textStorage?.attribute(.markdownLink, at: index, effectiveRange: nil) as? String
        else { return nil }
        return URL(string: destination)
    }

    // MARK: Lines

    struct Line {
        /// The line without its terminator.
        let range: NSRange
        let text: String
        let units: [UInt16]
        let scan: MarkdownLineScan

        func substring(_ range: Range<Int>) -> String {
            String(decoding: units[range], as: UTF16.self)
        }

        /// Where the quote prefix ends; 0 when there is none.
        var quoteEnd: Int {
            guard let last = scan.quoteMarkers.last else { return 0 }
            let after = last + 1
            return after < units.count && (units[after] == 0x20 || units[after] == 0x09) ? after + 1 : after
        }

        var isBlank: Bool {
            units.allSatisfy { $0 == 0x20 || $0 == 0x09 }
        }
    }

    func line(at location: Int) -> Line {
        let string = textStorage!.mutableString
        let paragraph = string.paragraphRange(for: NSRange(location: min(location, string.length), length: 0))
        var length = paragraph.length
        while length > 0 {
            let unit = string.character(at: paragraph.location + length - 1)
            guard unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029 else { break }
            length -= 1
        }
        let range = NSRange(location: paragraph.location, length: length)
        let text = string.substring(with: range)
        var entry = MarkdownLineState.normal
        if paragraph.length > 0, let stored = textStorage?.attribute(.markdownLineState, at: paragraph.location, effectiveRange: nil) as? Int {
            entry = MarkdownLineState(rawValue: stored)
        }
        return Line(range: range, text: text, units: Array(text.utf16), scan: scanMarkdownLine(text, entry: entry))
    }

    /// The lines a range touches, top to bottom.
    private func lines(in range: NSRange) -> [Line] {
        let string = textStorage!.mutableString
        let paragraphs = string.paragraphRange(for: range)
        var result: [Line] = []
        var location = paragraphs.location
        repeat {
            let line = line(at: location)
            result.append(line)
            location = NSMaxRange(string.paragraphRange(for: NSRange(location: location, length: 0)))
        } while location < NSMaxRange(paragraphs)
        return result
    }

    // MARK: Editing primitives

    /// Insert at the selection, leaving the caret after it.
    private func insert(_ string: String) {
        let selection = selectedRange()
        replace(selection, with: string, select: NSRange(location: selection.location + string.utf16.count, length: 0))
    }

    // MARK: Tasks

    func toggleTask(boxAt box: Int) {
        guard let storage = textStorage, box + 1 < storage.length else { return }
        let mark = NSRange(location: box + 1, length: 1)
        let isChecked = storage.mutableString.character(at: mark.location) != 0x20
        replace(mark, with: isChecked ? " " : "x", select: selectedRange())
    }

    // MARK: Return, Tab, Backspace

    /// Return inside a list, quote or code block carries its prefix onto the new line. Returns
    /// false to let the text view insert a plain newline.
    func continueBlockOnNewline() -> Bool {
        let selection = selectedRange()
        let line = line(at: selection.location)
        guard NSMaxRange(selection) <= NSMaxRange(line.range) else { return false }
        let caret = selection.location - line.range.location
        let scan = line.scan
        let contentIsEmpty = line.units[min(scan.contentStart, line.units.count)...].allSatisfy { $0 == 0x20 || $0 == 0x09 }

        if let list = scan.list, caret >= scan.contentStart {
            if contentIsEmpty {
                // Return on an empty item steps out a level, then out of the list.
                if list.indent > 0, indentLines(outdent: true) { return true }
                let quoteEnd = line.quoteEnd
                replace(
                    NSRange(location: line.range.location + quoteEnd, length: line.range.length - quoteEnd),
                    with: "",
                    select: NSRange(location: line.range.location + quoteEnd, length: 0)
                )
                return true
            }
            var marker: String
            switch list.kind {
            case .bullet:
                marker = line.substring(list.range.lowerBound..<(list.range.lowerBound + 1)) + " "
            case let .ordered(number, delimiter):
                marker = "\(number + 1)" + String(decoding: [delimiter], as: UTF16.self) + " "
            }
            if list.task != nil { marker += "[ ] " }
            insert("\n" + line.substring(0..<list.range.lowerBound) + marker)
            return true
        }
        if !scan.quoteMarkers.isEmpty, caret >= scan.contentStart {
            if contentIsEmpty {
                replace(line.range, with: "", select: NSRange(location: line.range.location, length: 0))
            } else {
                insert("\n" + line.substring(0..<scan.contentStart))
            }
            return true
        }
        if scan.block == .code {
            let indent = line.units.prefix { $0 == 0x20 || $0 == 0x09 }.count
            insert("\n" + line.substring(0..<min(indent, caret)))
            return true
        }
        return false
    }

    /// Tab and Shift-Tab on list items nest and unnest them. Returns false when the selection
    /// is not on list items, so Tab keeps its usual meaning.
    @discardableResult
    func indentLines(outdent: Bool) -> Bool {
        let selection = selectedRange()
        let touched = lines(in: selection)
        guard let first = touched.first, let firstList = first.scan.list,
              touched.allSatisfy({ $0.scan.list != nil || $0.isBlank }) else { return false }

        let delta = indentDelta(for: first, list: firstList, outdent: outdent)
        guard delta != 0 else { return true }

        var replacement = ""
        var firstShift = 0
        var totalShift = 0
        let string = textStorage!.mutableString
        let whole = string.paragraphRange(for: selection)
        for (index, line) in touched.enumerated() {
            let paragraph = string.paragraphRange(for: NSRange(location: line.range.location, length: 0))
            var text = string.substring(with: paragraph)
            if line.scan.list != nil {
                let quoteEnd = line.quoteEnd
                let utf16 = Array(text.utf16)
                let leading = utf16[quoteEnd...].prefix { $0 == 0x20 }.count
                let change = delta > 0 ? delta : -min(-delta, leading)
                let prefix = String(decoding: utf16[0..<quoteEnd], as: UTF16.self)
                let rest = String(decoding: utf16[(quoteEnd + leading)...], as: UTF16.self)
                text = prefix + String(repeating: " ", count: leading + change) + rest
                if index == 0 { firstShift = change }
                totalShift += change
            }
            replacement += text
        }

        let newSelection: NSRange
        if touched.count == 1 {
            let lineStart = first.range.location + first.quoteEnd
            newSelection = NSRange(location: max(lineStart, selection.location + firstShift), length: selection.length)
        } else {
            newSelection = NSRange(location: whole.location, length: max(0, whole.length + totalShift - 1))
        }
        replace(whole, with: replacement, select: newSelection)
        return true
    }

    /// How far to move a list line: in, to nest under the item above; out, to its parent's level.
    private func indentDelta(for line: Line, list: MarkdownListMarker, outdent: Bool) -> Int {
        var previous: MarkdownListMarker?
        var location = line.range.location
        // The nearest list item above at the relevant depth.
        while location > 0 {
            let above = self.line(at: location - 1)
            location = above.range.location
            guard let aboveList = above.scan.list else {
                if above.isBlank { continue }
                break
            }
            if outdent ? aboveList.indent < list.indent : aboveList.indent <= list.indent {
                previous = aboveList
                break
            }
        }
        if outdent {
            return (previous?.indent ?? 0) - list.indent
        }
        // Nesting needs a sibling above to nest under, and lines up with its text.
        guard let previous, previous.indent == list.indent else { return 0 }
        return previous.range.count
    }

    // Only typed text comes through here, so undoing a join restores the space for good.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        joinTagBeforeCaret()
    }

    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0, removePrefixBeforeCaret(selection.location) { return }
        super.deleteBackward(sender)
    }

    /// Backspace at the start of an item's text peels off one prefix: a task becomes a bullet,
    /// a bullet becomes text, a quote line loses its `>`.
    private func removePrefixBeforeCaret(_ caret: Int) -> Bool {
        let line = line(at: caret)
        let offset = caret - line.range.location
        guard offset > 0, offset == line.scan.contentStart else { return false }
        let start = line.range.location
        if let list = line.scan.list {
            let removed = list.task.map { $0.range.lowerBound..<offset } ?? list.range
            replace(
                NSRange(location: start + removed.lowerBound, length: removed.count),
                with: "",
                select: NSRange(location: start + removed.lowerBound, length: 0)
            )
            return true
        }
        if let firstQuote = line.scan.quoteMarkers.first {
            replace(
                NSRange(location: start + firstQuote, length: offset - firstQuote),
                with: "",
                select: NSRange(location: start + firstQuote, length: 0)
            )
            return true
        }
        return false
    }

    // MARK: Formatting shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (flags, event.charactersIgnoringModifiers?.lowercased()) {
        case ([.command], "b"): toggleWrap("**")
        case ([.command], "i"): toggleWrap("_")
        case ([.command, .shift], "x"): toggleWrap("~~")
        case ([.command], "k"): insertLink()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// The selection without surrounding whitespace, which would stop emphasis from closing.
    private func trimmedSelection() -> NSRange {
        let string = textStorage!.mutableString
        var range = selectedRange()
        while range.length > 0, isSpace(string.character(at: range.location)) {
            range.location += 1
            range.length -= 1
        }
        while range.length > 0, isSpace(string.character(at: NSMaxRange(range) - 1)) {
            range.length -= 1
        }
        return range
    }

    private func isSpace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A
    }

    /// Wrap the selection in `marker`, or unwrap it if it already is.
    func toggleWrap(_ marker: String) {
        let string = textStorage!.mutableString
        let width = marker.utf16.count
        let selection = trimmedSelection()
        func text(_ location: Int, _ length: Int) -> String? {
            guard location >= 0, location + length <= string.length else { return nil }
            return string.substring(with: NSRange(location: location, length: length))
        }

        if selection.length == 0 {
            if text(selection.location - width, width * 2) == marker + marker {
                replace(
                    NSRange(location: selection.location - width, length: width * 2),
                    with: "",
                    select: NSRange(location: selection.location - width, length: 0)
                )
            } else {
                replace(selection, with: marker + marker, select: NSRange(location: selection.location + width, length: 0))
            }
            return
        }

        let selected = string.substring(with: selection)
        if text(selection.location - width, width) == marker, text(NSMaxRange(selection), width) == marker {
            replace(
                NSRange(location: selection.location - width, length: selection.length + width * 2),
                with: selected,
                select: NSRange(location: selection.location - width, length: selection.length)
            )
        } else if selection.length >= width * 2, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let units = Array(selected.utf16)
            let inner = String(decoding: units[width..<(units.count - width)], as: UTF16.self)
            replace(selection, with: inner, select: NSRange(location: selection.location, length: inner.utf16.count))
        } else {
            replace(
                selection,
                with: marker + selected + marker,
                select: NSRange(location: selection.location + width, length: selection.length)
            )
        }
    }

    /// Cmd-K: make the selection a link, using a URL on the clipboard when there is one.
    func insertLink() {
        let selection = trimmedSelection()
        let selected = textStorage!.mutableString.substring(with: selection)
        let url = Self.clipboardURL()
        let replacement = "[\(selected)](\(url ?? ""))"
        // Into the brackets when there is no text, into the parens when there is no URL.
        let caret: Int
        if selected.isEmpty {
            caret = selection.location + 1
        } else if url == nil {
            caret = selection.location + replacement.utf16.count - 1
        } else {
            caret = selection.location + replacement.utf16.count
        }
        replace(selection, with: replacement, select: NSRange(location: caret, length: 0))
    }

    /// The clipboard's text if it is a single web or mail URL.
    static func clipboardURL() -> String? {
        guard let string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty, !string.contains(where: \.isWhitespace),
              let url = URL(string: string), let scheme = url.scheme?.lowercased()
        else { return nil }
        switch scheme {
        case "http", "https": return url.host == nil ? nil : string
        case "mailto": return string
        default: return nil
        }
    }

    // MARK: Paste

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        // Slack's plain-text flavour drops emphasis and link URLs; its Chromium flavour has markdown.
        if let data = pasteboard.data(forType: .chromiumWebCustomData),
           let markdown = slackMarkdown(fromWebCustomData: data), !markdown.isEmpty {
            insert(markdown)
            return
        }
        let selection = selectedRange()
        if selection.length > 0, let url = Self.clipboardURL() {
            let selected = textStorage!.mutableString.substring(with: selection)
            if !selected.contains(where: \.isNewline) {
                insert("[\(selected)](\(url))")
                return
            }
        }
        super.paste(sender)
    }

    /// The Slack button: Slack markdown when the clipboard came from Slack, else its plain text.
    func pasteFromSlack() {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .chromiumWebCustomData),
           let markdown = slackMarkdown(fromWebCustomData: data), !markdown.isEmpty {
            insert(markdown)
        } else if let string = pasteboard.string(forType: .string), !string.isEmpty {
            insert(string)
        }
    }
}

extension NSPasteboard.PasteboardType {
    /// Chromium's custom-format flavour. Not in AppKit: Electron apps write it for the web
    /// `DataTransfer` API, and it is where Slack puts the formatting the plain text loses.
    static let chromiumWebCustomData = NSPasteboard.PasteboardType("org.chromium.web-custom-data")
}
