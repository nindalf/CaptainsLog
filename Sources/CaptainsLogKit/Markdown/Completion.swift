import Foundation

// Detection and ranking for inline completion in a markdown field: `@` for people, `#` for pull
// requests. Pure string work so it can be tested without a view — the editor supplies the caret
// offset and turns the result into a suggestion list.

/// Characters that open an inline completion.
public enum CompletionTrigger: Character, CaseIterable, Sendable {
    case person = "@"
    case pullRequest = "#"
}

/// An in-progress completion token sitting immediately before the caret.
public struct CompletionQuery: Equatable, Sendable {
    public let trigger: CompletionTrigger
    /// Character offset of the trigger character.
    public let start: Int
    /// Character offset of the caret, i.e. one past the last typed character.
    public let end: Int
    /// What has been typed after the trigger. Empty right after typing it.
    public let prefix: String

    public init(trigger: CompletionTrigger, start: Int, end: Int, prefix: String) {
        self.trigger = trigger
        self.start = start
        self.end = end
        self.prefix = prefix
    }
}

/// Longest prefix worth searching on. Past this the user is clearly writing prose rather than
/// completing a name, and the list should get out of the way.
private let maximumCompletionPrefix = 32

/// Find the completion token the caret is currently inside, if any.
///
/// The prefix may contain spaces, since names and PR titles do — `@Alice Sm` has to be able to
/// match "Alice Smith". Nothing else terminates the token, so one that stops matching anything
/// simply produces no candidates and the list closes on its own.
///
/// Three rules keep this out of the way of ordinary markdown:
/// - The trigger must start a word, so `james.kirk@larder.co.uk` and the second `#` of `##` are inert.
/// - The prefix may not *end* in whitespace. That is what tells an already-completed
///   `@Alice Smith ` apart from someone midway through typing it, so accepting a suggestion
///   closes the list instead of re-offering the name just inserted.
/// - The prefix may not *start* with whitespace, which is what keeps `# Heading` and `## Key` from
///   opening a pull-request list.
public func completionQuery(in text: String, caretOffset: Int) -> CompletionQuery? {
    let characters = Array(text)
    guard caretOffset >= 0, caretOffset <= characters.count else { return nil }

    var index = caretOffset - 1
    var trigger: CompletionTrigger?
    while index >= 0 {
        let character = characters[index]
        if let match = CompletionTrigger(rawValue: character) {
            trigger = match
            break
        }
        // A completion cannot span lines.
        if character.isNewline { return nil }
        index -= 1
    }
    guard let trigger, index >= 0 else { return nil }

    // The trigger has to start a word. Also what makes `##` inert: the second `#` is preceded by
    // the first, which is not a boundary.
    if index > 0 {
        let preceding = characters[index - 1]
        guard preceding.isWhitespace || preceding == "(" || preceding == "[" else { return nil }
    }

    let prefix = String(characters[(index + 1)..<caretOffset])
    guard prefix.count <= maximumCompletionPrefix else { return nil }
    guard prefix.first?.isWhitespace != true, prefix.last?.isWhitespace != true else { return nil }
    return CompletionQuery(trigger: trigger, start: index, end: caretOffset, prefix: prefix)
}

// MARK: - Ranking

/// Rank a person against what has been typed. Lower sorts first; nil means no match.
///
/// The tiers matter more than the numbers: a name starting with the prefix beats a *surname*
/// starting with it, which beats a handle, which beats a mid-word substring. An empty prefix
/// matches everyone, so typing a bare `@` lists all people.
public func mentionMatchScore(prefix: String, name: String, handles: [String?] = []) -> Int? {
    let needle = prefix.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else { return 0 }

    let haystack = name.lowercased()
    if haystack.hasPrefix(needle) { return 0 }
    if haystack.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return 1 }
    for handle in handles.compactMap({ $0?.lowercased() }) where handle.hasPrefix(needle) {
        return 2
    }
    if haystack.contains(needle) { return 3 }
    return nil
}

/// Rank a pull request against what has been typed. Lower sorts first; nil means no match.
///
/// A numeric prefix matches the number, which is the common case (`#45` -> #4521). Everything else
/// searches the title, then the repo, so `#backfill` finds the PR you remember by name.
public func pullRequestMatchScore(
    prefix: String,
    number: Int,
    title: String,
    repo: String = ""
) -> Int? {
    let needle = prefix.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else { return 0 }

    if String(number).hasPrefix(needle) { return 0 }
    let haystack = title.lowercased()
    if haystack.hasPrefix(needle) { return 1 }
    if haystack.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return 2 }
    if repo.lowercased().contains(needle) { return 3 }
    if haystack.contains(needle) { return 4 }
    return nil
}

/// Order for the pull-request suggestion list: best match first, highest number first within a
/// tier, so the newest PR leads. The number has to be an explicit tiebreak — `Array.sort` is not
/// guaranteed stable, so equal scores would otherwise come out in an unspecified order, which is
/// every row when the prefix is empty.
public func pullRequestSuggestionPrecedes(
    _ lhs: (score: Int, number: Int),
    _ rhs: (score: Int, number: Int)
) -> Bool {
    lhs.score == rhs.score ? lhs.number > rhs.number : lhs.score < rhs.score
}

// MARK: - Possessives

/// A space to take back out after a tag. Accepting a suggestion inserts `@alice `, so typing a
/// possessive straight after it gives `@alice 's`; this turns that into `@alice's`, and
/// `@james ' ` into `@james' `.
public struct PossessiveJoin: Equatable, Sendable {
    /// Character offset of the space between the tag and the apostrophe.
    public let start: Int
    /// Replaces the space and the apostrophe: the apostrophe alone, a curly one as `’`.
    public let replacement: String
}

/// Whether the two characters before the caret could end a join. Constant time, so an editor
/// can run it on every keystroke and only call `possessiveJoin`, which walks the text, when it
/// passes.
public func mayEndPossessive(apostrophe: Character, last: Character) -> Bool {
    // A smart-quoting editor curls an apostrophe after a space the wrong way, as an opening quote.
    (last == "s" || last == " ") && ["'", "\u{2018}", "\u{2019}"].contains(apostrophe)
}

/// The join to make if the caret sits just after a tag followed by ` 's` or ` ' `. The tag is
/// anything `completionQuery` would read as one, so it may be a name with spaces in it.
public func possessiveJoin(in text: String, caretOffset: Int) -> PossessiveJoin? {
    let characters = Array(text)
    guard caretOffset >= 3, caretOffset <= characters.count else { return nil }
    let space = caretOffset - 3
    let apostrophe = characters[space + 1]
    guard characters[space] == " ",
          mayEndPossessive(apostrophe: apostrophe, last: characters[space + 2]) else { return nil }
    let replacement = apostrophe == "'" ? "'" : "\u{2019}"
    guard let tag = completionQuery(in: String(characters[..<space]), caretOffset: space),
          !tag.prefix.isEmpty else { return nil }
    return PossessiveJoin(start: space, replacement: replacement)
}

// MARK: - Punctuation

/// Punctuation that sits against the tag before it. Accepting a suggestion inserts `@alice `, so
/// typing `?` straight after gives `@alice ?`; `punctuationJoin` takes the space back out.
private let tagClosingPunctuation: Set<Character> = [",", ".", "?", "!", ";", ":", ")"]

/// Whether the two characters before the caret could end a punctuation join. Constant time, like
/// `mayEndPossessive`.
public func mayEndPunctuation(space: Character, last: Character) -> Bool {
    space == " " && tagClosingPunctuation.contains(last)
}

/// Character offset of the space to remove if the caret sits just after a tag followed by a space
/// and one of `, . ? ! ; : )`. The tag is anything `completionQuery` would read as one.
public func punctuationJoin(in text: String, caretOffset: Int) -> Int? {
    let characters = Array(text)
    guard caretOffset >= 2, caretOffset <= characters.count else { return nil }
    let space = caretOffset - 2
    guard mayEndPunctuation(space: characters[space], last: characters[space + 1]),
          let tag = completionQuery(in: String(characters[..<space]), caretOffset: space),
          !tag.prefix.isEmpty else { return nil }
    return space
}

// MARK: - Insertion

/// The text a selected person contributes to the field, including the trailing space that lets
/// typing continue naturally. Their Slack handle, so the note reads the way Slack does, falling
/// back to the name for people without one.
public func mentionInsertion(name: String, slackHandle: String?) -> String {
    let handle = slackHandle?
        .trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    if let handle, !handle.isEmpty { return "@\(handle) " }
    return "@\(name) "
}

/// The text a selected pull request contributes to the field. Bare `#1234`, the GitHub
/// convention, so it stays parseable for click-to-navigate later.
public func pullRequestInsertion(number: Int) -> String {
    "#\(number) "
}
