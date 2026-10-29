import Foundation

/// Where a search query matched a record: the field that best contains it, and the text around
/// the match. Matching ignores case and diacritics, like `localizedStandardContains`, and counts
/// only at the start of a word, so "tom" finds "Tom" but not "customer".
public struct SearchMatch: Sendable, Equatable {
    public let field: String
    public let snippet: String

    public init(field: String, snippet: String) {
        self.field = field
        self.snippet = snippet
    }

    /// The words of a query. A record matches when every word appears in one of its fields.
    public static func terms(of query: String) -> [String] {
        var seen: Set<String> = []
        return query.split(whereSeparator: \.isWhitespace).map(String.init).filter {
            seen.insert($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted
        }
    }

    /// Nil unless every word of `query` appears in some field. The field reported is the first, in
    /// order, holding the most words. The snippet is at most `length` characters, starting a little
    /// before that field's earliest match, with whitespace runs collapsed and an ellipsis where text was cut.
    public static func first(_ query: String, in fields: [(name: String, text: String?)], length: Int = 200) -> SearchMatch? {
        let terms = terms(of: query)
        guard !terms.isEmpty else { return nil }
        var unmatched = Set(terms.indices)
        var best: (name: String, text: String, count: Int, at: String.Index)?
        for (name, text) in fields {
            guard let text else { continue }
            let ranges = terms.indices.compactMap { i in wordStart(of: terms[i], in: text).map { (i, $0) } }
            guard let earliest = ranges.map(\.1.lowerBound).min() else { continue }
            unmatched.subtract(ranges.map(\.0))
            if ranges.count > best?.count ?? 0 {
                best = (name, text, ranges.count, earliest)
            }
        }
        guard unmatched.isEmpty, let best else { return nil }
        let text = best.text
        // A little before the match, but no later than needed to fill the snippet to the end of the text.
        // Cuts move to the nearest space inside, so no word is split.
        let lead = text.index(best.at, offsetBy: -(length / 4), limitedBy: text.startIndex) ?? text.startIndex
        var start = min(lead, text.index(text.endIndex, offsetBy: -length, limitedBy: text.startIndex) ?? text.startIndex)
        var end = text.index(start, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
        if start > text.startIndex, let space = text[start..<best.at].firstIndex(where: \.isWhitespace) {
            start = text.index(after: space)
        }
        if end < text.endIndex, let space = text[best.at..<end].lastIndex(where: \.isWhitespace) {
            end = space
        }
        var snippet = text[start..<end].replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
        if start > text.startIndex { snippet = "…" + snippet }
        if end < text.endIndex { snippet += "…" }
        return SearchMatch(field: best.name, snippet: snippet)
    }

    /// The first occurrence of `term` in `text` at or after `from` that starts a word: not preceded by a letter or digit.
    public static func wordStart(of term: String, in text: String, from: String.Index? = nil) -> Range<String.Index>? {
        var from = from ?? text.startIndex
        while let r = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex, locale: .current) {
            if r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetter && !text[text.index(before: r.lowerBound)].isNumber {
                return r
            }
            from = text.index(after: r.lowerBound)
        }
        return nil
    }

    /// Every word-start occurrence of any of `terms` in `text`, in order and not overlapping: what to highlight.
    public static func wordStarts(of terms: [String], in text: String) -> [Range<String.Index>] {
        var all: [Range<String.Index>] = []
        for term in terms where !term.isEmpty {
            var from = text.startIndex
            while from < text.endIndex, let r = wordStart(of: term, in: text, from: from) {
                all.append(r)
                from = r.upperBound
            }
        }
        var merged: [Range<String.Index>] = []
        for r in all.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, r.lowerBound < last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }
        return merged
    }
}
