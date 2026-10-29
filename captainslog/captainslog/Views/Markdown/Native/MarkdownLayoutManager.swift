import AppKit

// Draws what attributes alone cannot: code block and inline code backgrounds, blockquote bars,
// horizontal rules and task checkboxes. The highlighter marks where each goes with an attribute
// and leaves the underlying characters in place, transparent where something is drawn over them.
final class MarkdownLayoutManager: NSLayoutManager {
    private let theme = MarkdownTheme.shared

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // Behind the selection, which super draws.
        if let storage = textStorage, let container = textContainers.first, storage.length > 0 {
            let characters = paragraphs(around: glyphsToShow, in: storage)
            drawCodeBlocks(in: characters, storage: storage, container: container, origin: origin)
            drawInlineCode(in: characters, storage: storage, container: container, origin: origin)
            drawQuoteBars(in: characters, storage: storage, origin: origin)
            drawRules(in: characters, storage: storage, container: container, origin: origin)
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        if let storage = textStorage, storage.length > 0 {
            drawCheckboxes(in: paragraphs(around: glyphsToShow, in: storage), storage: storage, origin: origin)
        }
    }

    /// Widened to whole paragraphs: a bar or box belongs to its paragraph's first line, which can
    /// sit above the redrawn region when only a wrapped continuation is being drawn.
    private func paragraphs(around glyphs: NSRange, in storage: NSTextStorage) -> NSRange {
        let characters = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        return storage.mutableString.paragraphRange(for: characters)
    }

    // MARK: Blocks

    private func drawCodeBlocks(in characters: NSRange, storage: NSTextStorage, container: NSTextContainer, origin: NSPoint) {
        let all = NSRange(location: 0, length: storage.length)
        var location = characters.location
        while location < NSMaxRange(characters) {
            var block = NSRange()
            let value = storage.attribute(.markdownCodeBlock, at: location, longestEffectiveRange: &block, in: all)
            defer { location = max(NSMaxRange(block), location + 1) }
            guard value != nil, let lines = lineSpan(of: block) else { continue }
            let rect = NSRect(
                x: origin.x + 1,
                y: origin.y + lines.minY,
                width: container.size.width - 2,
                height: lines.height
            )
            theme.codeBackground.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }
    }

    private func drawInlineCode(in characters: NSRange, storage: NSTextStorage, container: NSTextContainer, origin: NSPoint) {
        storage.enumerateAttribute(.markdownInlineCode, in: characters) { value, range, _ in
            guard value != nil else { return }
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? theme.code
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            theme.codeBackground.setFill()
            enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, lineGlyphs, _ in
                let part = NSIntersectionRange(lineGlyphs, glyphs)
                guard part.length > 0 else { return }
                let bounds = self.boundingRect(forGlyphRange: part, in: container)
                let baseline = lineRect.minY + self.location(forGlyphAt: part.location).y
                let rect = NSRect(
                    x: origin.x + bounds.minX - 2,
                    y: origin.y + baseline - font.ascender - 1.5,
                    width: bounds.width + 4,
                    height: font.ascender - font.descender + 3
                )
                NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            }
        }
    }

    private func drawQuoteBars(in characters: NSRange, storage: NSTextStorage, origin: NSPoint) {
        theme.quoteBar.setFill()
        storage.enumerateAttribute(.markdownQuote, in: characters) { value, range, _ in
            guard value != nil else { return }
            // Adjacent `>`s of a nested quote come through as one range.
            for index in range.location..<NSMaxRange(range) {
                let paragraph = storage.mutableString.paragraphRange(for: NSRange(location: index, length: 0))
                guard let lines = lineSpan(of: paragraph) else { continue }
                let glyph = glyphIndexForCharacter(at: index)
                let lineRect = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let x = lineRect.minX + location(forGlyphAt: glyph).x
                let rect = NSRect(x: origin.x + x + 1, y: origin.y + lines.minY, width: 3, height: lines.height)
                NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
    }

    private func drawRules(in characters: NSRange, storage: NSTextStorage, container: NSTextContainer, origin: NSPoint) {
        storage.enumerateAttribute(.markdownRule, in: characters) { value, range, _ in
            guard value != nil else { return }
            let lineRect = lineFragmentRect(forGlyphAt: glyphIndexForCharacter(at: range.location), effectiveRange: nil)
            let spacing = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing ?? 0
            let y = (origin.y + lineRect.minY + (lineRect.height - spacing) / 2).rounded(.down) + 0.5
            let path = NSBezierPath()
            path.move(to: NSPoint(x: origin.x + container.lineFragmentPadding, y: y))
            path.line(to: NSPoint(x: origin.x + container.size.width - container.lineFragmentPadding, y: y))
            path.lineWidth = 1
            theme.rule.setStroke()
            path.stroke()
        }
    }

    /// The vertical extent of the lines laid out for a character range.
    private func lineSpan(of characters: NSRange) -> (minY: CGFloat, height: CGFloat)? {
        let glyphs = glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        let first = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let last = lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
        return (first.minY, last.maxY - first.minY)
    }

    // MARK: Checkboxes

    private func drawCheckboxes(in characters: NSRange, storage: NSTextStorage, origin: NSPoint) {
        storage.enumerateAttribute(.markdownTask, in: characters) { value, range, _ in
            guard let isChecked = value as? Bool else { return }
            let rect = checkboxRect(forCharacterAt: range.location, storage: storage)
                .offsetBy(dx: origin.x, dy: origin.y)
            drawCheckbox(in: rect, isChecked: isChecked)
        }
    }

    /// Where the box for the task whose `[` is at `index` is drawn, in container coordinates.
    func checkboxRect(forCharacterAt index: Int, storage: NSTextStorage) -> NSRect {
        let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? theme.body
        let glyph = glyphIndexForCharacter(at: index)
        let lineRect = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let location = location(forGlyphAt: glyph)
        let side = (font.capHeight + 4).rounded()
        let baseline = lineRect.minY + location.y
        return NSRect(
            x: (lineRect.minX + location.x).rounded() + 0.5,
            y: (baseline - font.capHeight / 2 - side / 2).rounded(),
            width: side,
            height: side
        )
    }

    private func drawCheckbox(in rect: NSRect, isChecked: Bool) {
        let radius = rect.width * 0.27
        if isChecked {
            theme.checkboxFill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.53))
            check.line(to: NSPoint(x: rect.minX + rect.width * 0.43, y: rect.minY + rect.height * 0.70))
            check.line(to: NSPoint(x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 0.32))
            check.lineWidth = 1.7
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            let box = NSBezierPath(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), xRadius: radius, yRadius: radius)
            box.lineWidth = 1.2
            theme.checkboxStroke.setStroke()
            box.stroke()
        }
    }
}
