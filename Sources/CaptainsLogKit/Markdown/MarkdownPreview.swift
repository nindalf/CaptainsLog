import Foundation
import Markdown

/// Markdown flattened to one line of plain text for list-row snippets: markers dropped, blocks
/// joined by spaces. Only the first `limit` characters are parsed; a row shows far fewer.
public func markdownPreview(_ markdown: String, limit: Int = 500) -> String {
    let document = Markdown.Document(parsing: String(markdown.prefix(limit)))
    var parts: [String] = []
    collectBlocks(document, into: &parts)
    return parts
        .joined(separator: " ")
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
}

private func collectBlocks(_ markup: Markup, into parts: inout [String]) {
    switch markup {
    case let code as CodeBlock:
        parts.append(code.code)
    case is ThematicBreak, is HTMLBlock:
        break
    case let container as InlineContainer:
        parts.append(inlineText(container))
    default:
        for child in markup.children {
            collectBlocks(child, into: &parts)
        }
    }
}

private func inlineText(_ markup: Markup) -> String {
    switch markup {
    case let text as Markdown.Text:
        text.string
    case let code as InlineCode:
        code.code
    case is SoftBreak, is LineBreak:
        " "
    case is InlineHTML:
        ""
    default:
        markup.children.map(inlineText).joined()
    }
}
