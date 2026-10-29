import Foundation
import Markdown

/// Convert markdown to the small HTML subset Slack's message composer understands on paste.
///
/// Slack's composer is a rich-text editor: pasted plain text is inserted verbatim, so mrkdwn
/// markers (`*bold*`, a literal `•`, `<url|label>`) arrive as literal characters. Pasted HTML
/// is parsed instead, so this is the only route to real Slack bullets, labelled links and
/// emphasis.
///
/// Mapping: `**b**` -> `<strong>`, `*i*`/`_i_` -> `<em>`, `~~s~~` -> `<s>`, `` `c` `` ->
/// `<code>`, fenced code -> `<pre><code>`, `[t](u)` -> `<a href="u">t</a>`, `- ` -> `<ul><li>`,
/// `1. ` -> `<ol><li>`, `> ` -> `<blockquote>`. Headings become a bold paragraph: Slack messages
/// have no heading style.
public func markdownToSlackHTML(_ markdown: String) -> String {
    let blocks = Array(Markdown.Document(parsing: markdown).children)
    var html = ""
    for (index, block) in blocks.enumerated() {
        if index > 0, blankLineSeparates(blocks[index - 1], block) {
            html += "<p><br></p>"
        }
        html += htmlBlock(block)
    }
    return html
}

/// Slack gives paragraphs no margin, so a blank line in the note survives only as an empty
/// paragraph. Several blank lines in a row still make one.
private func blankLineSeparates(_ previous: Markup, _ next: Markup) -> Bool {
    guard let end = lastContentLine(of: previous), let start = next.range?.lowerBound.line else { return false }
    return start > end + 1
}

/// A list's range runs on over the blank line after it, so measure from its deepest last child.
private func lastContentLine(of markup: Markup) -> Int? {
    var node = markup
    while node.childCount > 0, let last = node.child(at: node.childCount - 1), last.range != nil {
        node = last
    }
    return node.range?.upperBound.line
}

// MARK: - Block rendering

private func htmlBlock(_ markup: Markup) -> String {
    switch markup {
    case let heading as Heading:
        return "<p><strong>" + htmlInlineChildren(heading) + "</strong></p>"
    case let paragraph as Paragraph:
        return "<p>" + htmlInlineChildren(paragraph) + "</p>"
    case let list as UnorderedList:
        return "<ul>" + list.listItems.map { "<li>" + htmlListItem($0) + "</li>" }.joined() + "</ul>"
    case let list as OrderedList:
        return "<ol>" + list.listItems.map { "<li>" + htmlListItem($0) + "</li>" }.joined() + "</ol>"
    case let quote as BlockQuote:
        return "<blockquote>" + quote.children.map(htmlBlock).joined() + "</blockquote>"
    case let code as CodeBlock:
        let body = code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code
        return "<pre><code>" + escapeHTML(body) + "</code></pre>"
    case is ThematicBreak:
        return "<hr>"
    default:
        // Tables, HTML blocks, etc.: fall back to a paragraph of inline children.
        return "<p>" + htmlInlineChildren(markup) + "</p>"
    }
}

/// A list item's own paragraph is unwrapped: `<li><p>x</p></li>` renders as a bullet followed by
/// a blank line in Slack. Nested lists keep their tags so they nest inside the `<li>`.
private func htmlListItem(_ item: ListItem) -> String {
    item.children.map { child in
        if let paragraph = child as? Paragraph {
            return htmlInlineChildren(paragraph)
        }
        return htmlBlock(child)
    }
    .joined()
}

// MARK: - Inline rendering

private func htmlInlineChildren(_ markup: Markup) -> String {
    markup.children.map(htmlInline).joined()
}

private func htmlInline(_ markup: Markup) -> String {
    switch markup {
    case let text as Text:
        return escapeHTML(text.string)
    case let strong as Strong:
        return "<strong>" + htmlInlineChildren(strong) + "</strong>"
    case let emphasis as Emphasis:
        return "<em>" + htmlInlineChildren(emphasis) + "</em>"
    case let strike as Strikethrough:
        return "<s>" + htmlInlineChildren(strike) + "</s>"
    case let code as InlineCode:
        return "<code>" + escapeHTML(code.code) + "</code>"
    case let link as Link:
        let label = htmlInlineChildren(link)
        guard let destination = link.destination, !destination.isEmpty else { return label }
        let text = label.isEmpty ? escapeHTML(destination) : label
        return "<a href=\"" + escapeHTMLAttribute(destination) + "\">" + text + "</a>"
    case is SoftBreak, is LineBreak:
        // A single newline in the editor reads as a line break, so keep it as one rather than
        // collapsing it to a space the way CommonMark would.
        return "<br>"
    case let inlineHTML as InlineHTML:
        return inlineHTML.rawHTML
    default:
        return htmlInlineChildren(markup)
    }
}

// MARK: - Escaping

private func escapeHTML(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

private func escapeHTMLAttribute(_ string: String) -> String {
    escapeHTML(string).replacingOccurrences(of: "\"", with: "&quot;")
}
