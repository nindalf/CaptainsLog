import AppKit
import CaptainsLogKit

// Fonts, colours and paragraph styles for the native markdown editor. Everything is built once
// and cached: the highlighter asks for these on every restyled line, and NSFont/NSParagraphStyle
// construction is far slower than a dictionary lookup.

extension NSAttributedString.Key {
    /// `MarkdownLineState.rawValue` the line was styled with, on every unit of the line. Lets a
    /// restyle stop at the first line whose stored state already matches.
    static let markdownLineState = NSAttributedString.Key("CLMarkdownLineState")
    /// Units laid out with no width and not drawn: a task's `- `.
    static let markdownHidden = NSAttributedString.Key("CLMarkdownHidden")
    /// On the three units of a task box; the value is whether it is checked.
    static let markdownTask = NSAttributedString.Key("CLMarkdownTask")
    /// On every line of a fenced code block, fences included.
    static let markdownCodeBlock = NSAttributedString.Key("CLMarkdownCodeBlock")
    static let markdownInlineCode = NSAttributedString.Key("CLMarkdownInlineCode")
    /// On each `>` of a blockquote prefix; a bar is drawn in its place.
    static let markdownQuote = NSAttributedString.Key("CLMarkdownQuote")
    static let markdownRule = NSAttributedString.Key("CLMarkdownRule")
    /// A link's destination, on the whole link.
    static let markdownLink = NSAttributedString.Key("CLMarkdownLink")
}

final class MarkdownTheme {
    static let shared = MarkdownTheme()

    let bodySize = NSFont.systemFontSize
    let body: NSFont
    let code: NSFont

    let text = NSColor.labelColor
    let secondary = NSColor.secondaryLabelColor
    let syntax = NSColor.tertiaryLabelColor
    let link = NSColor.linkColor
    let placeholder = NSColor.placeholderTextColor
    let quoteBar = NSColor.quaternaryLabelColor
    let rule = NSColor.separatorColor
    let checkboxStroke = NSColor.tertiaryLabelColor
    let checkboxFill = NSColor.controlAccentColor
    let codeBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.07)
            : NSColor(white: 0, alpha: 0.045)
    }

    /// Extra space after the `]` of a task box, so text clears the drawn checkbox.
    let taskKern: CGFloat = 3.5
    /// Extra space after each space indenting a list item, so two-space nesting reads as nesting.
    let indentKern: CGFloat = 2.5
    let codeInset: CGFloat = 6

    private var fonts: [FontKey: NSFont] = [:]
    private var paragraphStyles: [ParagraphKey: NSParagraphStyle] = [:]
    private var prefixWidths: [String: CGFloat] = [:]

    private init() {
        body = .systemFont(ofSize: bodySize)
        code = .monospacedSystemFont(ofSize: bodySize - 1, weight: .regular)
    }

    // MARK: Fonts

    enum FontRole: Hashable {
        case body
        case heading(Int)
        case code
    }

    private struct FontKey: Hashable {
        let role: FontRole
        let strong: Bool
        let emphasis: Bool
        let code: Bool
    }

    func font(_ role: FontRole, _ style: MarkdownInlineStyle = []) -> NSFont {
        let key = FontKey(
            role: role,
            strong: style.contains(.strong),
            emphasis: style.contains(.emphasis),
            code: style.contains(.code)
        )
        if let font = fonts[key] { return font }
        let font = makeFont(key)
        fonts[key] = font
        return font
    }

    private func makeFont(_ key: FontKey) -> NSFont {
        var size = bodySize
        var weight = NSFont.Weight.regular
        if case let .heading(level) = key.role {
            (size, weight) = headingMetrics(level)
        }
        if key.strong, weight.rawValue < NSFont.Weight.semibold.rawValue { weight = .semibold }

        let base: NSFont
        if key.role == .code || key.code {
            // Monospaced text runs a point small next to proportional text of the same size.
            base = .monospacedSystemFont(ofSize: size - 1, weight: weight)
        } else {
            base = .systemFont(ofSize: size, weight: weight)
        }
        guard key.emphasis else { return base }
        let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    private func headingMetrics(_ level: Int) -> (CGFloat, NSFont.Weight) {
        switch level {
        case 1: (bodySize + 9, .bold)
        case 2: (bodySize + 5, .bold)
        case 3: (bodySize + 2, .semibold)
        default: (bodySize, .semibold)
        }
    }

    // MARK: Paragraphs

    enum ParagraphKind: Hashable {
        case body
        case heading(Int)
        case code
    }

    private struct ParagraphKey: Hashable {
        let kind: ParagraphKind
        let headIndent: CGFloat
    }

    func paragraphStyle(_ kind: ParagraphKind, headIndent: CGFloat = 0) -> NSParagraphStyle {
        let key = ParagraphKey(kind: kind, headIndent: (headIndent * 2).rounded() / 2)
        if let style = paragraphStyles[key] { return style }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 2
        switch kind {
        case .body:
            style.headIndent = key.headIndent
        case let .heading(level):
            style.paragraphSpacingBefore = level <= 2 ? 8 : 5
            style.paragraphSpacing = 3
        case .code:
            // Code lines butt together so their backgrounds form one block.
            style.paragraphSpacing = 0
            style.firstLineHeadIndent = codeInset
            style.headIndent = codeInset
            style.tailIndent = -codeInset
        }
        paragraphStyles[key] = style
        return style
    }

    // MARK: Measuring

    /// The body font's advance for a single character.
    func advance(of character: String) -> CGFloat {
        prefixWidth(character, extraKern: 0)
    }

    /// Width of a line's prefix as laid out; `display` is the prefix without its hidden units.
    func prefixWidth(_ display: String, extraKern: CGFloat) -> CGFloat {
        if let width = prefixWidths[display] { return width + extraKern }
        let width = (display as NSString).size(withAttributes: [.font: body]).width
        prefixWidths[display] = width
        return width + extraKern
    }
}
