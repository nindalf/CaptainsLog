# Native markdown editor

The app's only markdown editor, behind `MarkdownEditor`. It replaced Classic, a SwiftUI
`TextEditor` restyled whole on every keystroke. Both shipped for a while, with a switch in Settings
and a side-by-side lab with a benchmark; Classic, the switch and the lab were removed on 2026-10-26.
The sections below on Classic are why.

## Why Classic lagged

Every keystroke in Classic:

1. Parsed the whole note with swift-markdown, then converted each span's range with
   `String.distance(from: startIndex, to:)`, an O(n) walk over grapheme clusters, once per span.
   That is quadratic in the note's length.
2. Built a fresh `AttributedString` for the whole note and compared it against the old one.
3. Assigned it back to SwiftUI's `TextEditor`, which replaced its entire text storage and laid
   out every line again.
4. Wrote the model, re-rendering whatever observed it. Every editor also held two `@Query`s over
   all people and PRs, which re-ran on each save.

## What Native does instead

- **Restyle only what changed.** `MarkdownHighlighter` is the text storage's delegate. After an
  edit it restyles the touched lines and stops at the first line after them whose stored state
  matches. Each line stores the scanner state it was styled with (`markdownLineState`). The only
  state that crosses lines is an open code fence, so typing restyles one line, and only opening or
  closing a fence restyles further.
- **Scan in UTF-16.** `MarkdownLineScanner` (CaptainsLogKit) works on the code units
  `NSTextStorage` already holds, so there is no offset conversion. It implements CommonMark's
  emphasis rules, with the rule of three, plus code spans, escapes, links, bare URLs, headings,
  quotes, lists, tasks, rules and fences.
- **Cache styling.** Fonts, paragraph styles and prefix widths are built once in `MarkdownTheme`.
- **Draw decorations.** Checkboxes, code blocks, inline-code pills, quote bars and rules are drawn
  by `MarkdownLayoutManager`. The markdown characters stay in the storage, so the text is always
  the exact source.
- **Write the model in bursts.** The binding is written 500 ms after typing stops. It is also
  written before any click, command key, Return, Escape or Tab, so a button or list handler never
  reads stale text.
- **Fetch completions on demand.** People and PRs are fetched when a `@` or `#` list opens, not
  held in a live query.

## Numbers

From the lab (since removed) and a CPU-time measurement while typing (Debug build, M-series Mac):

| | Classic | Native |
|---|---|---|
| Restyle per keystroke, 1K-character note | 1.35 ms | 32 µs |
| Restyle per keystroke, 875-line note | 28 ms | 31 µs |
| App CPU typing 80 characters, 875-line note (lab) | 1.37 s | 0.28 s |
| App CPU typing 80 characters, short log card | 0.99 s | 0.34 s |

Classic's restyle figure leaves out the full re-layout that follows it. Most of Native's remaining
time is AppKit's own spelling and predictive-text work, which Classic pays too.

## Traps, each covered by a test or the code

- Restyle in `didProcessEditing`, not `willProcessEditing`. Attribute changes made in
  `willProcessEditing` widen the edited range the layout manager sees, and it then moves the caret
  to the end of the line (`typingKeepsTheCaretInPlace`).
- The dirty range runs through the line after the edit. An inserted newline ends the edited range,
  and the text after it is a new line with changed content (`randomEditsMatchAFreshStyle`, which
  checks that incremental restyling always equals a fresh one).
- Never write the binding during a SwiftUI update. Reading it back in the same update returns the
  old value, and a write to `@State` can be dropped. Writes that may happen inside an update
  (losing focus, teardown, a field switched to another note) are deferred.
- SwiftUI `onKeyPress` handlers on ancestors run before the text view gets the key. That is why
  `MarkdownEditor` attaches its own Return, Tab, arrow and Escape handlers to the field, so they
  run first.

## Not yet

Inline spans don't cross lines. No setext headings or reference links. TextKit 1 limits Writing
Tools to its panel. Never checked in light mode.
