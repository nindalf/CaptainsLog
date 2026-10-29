import AppKit
import SwiftUI
import CaptainsLogKit

/// Focus-value type used by the focus-less `MarkdownEditor` initializer.
enum MarkdownEditorNoFocus: Hashable {}

/// Multi-line editor for markdown-backed note fields. The model stays a plain markdown `String`.
/// Generic over an optional `FocusState` value so the Todo and Log cards can drive and observe
/// focus and intercept Return.
struct MarkdownEditor<Focus: Hashable>: View {
    @Binding private var text: String
    private let placeholder: String
    private let minHeight: CGFloat
    private let maxHeight: CGFloat?
    private let showSlackControls: Bool
    private let copyHelp: String
    private let focus: FocusState<Focus?>.Binding?
    private let focusValue: Focus?
    private let onReturn: (() -> Void)?

    @State private var handle = MarkdownEditorHandle()

    /// Focus-aware initializer for the Todo / Log cards.
    init(
        text: Binding<String>,
        placeholder: String = "",
        minHeight: CGFloat = 20,
        maxHeight: CGFloat? = nil,
        showSlackControls: Bool = true,
        copyHelp: String = "Copy for Slack",
        focus: FocusState<Focus?>.Binding,
        focusValue: Focus,
        onReturn: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.showSlackControls = showSlackControls
        self.copyHelp = copyHelp
        self.focus = focus
        self.focusValue = focusValue
        self.onReturn = onReturn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showSlackControls {
                MarkdownSlackControls(
                    copyHelp: copyHelp,
                    copy: { copyMarkdownForSlack(text) },
                    paste: { handle.controller?.textView.pasteFromSlack() }
                )
            }
            nativeFieldWithFocus
        }
    }

    @ViewBuilder
    private var nativeFieldWithFocus: some View {
        if let focus, let focusValue {
            nativeField.focused(focus, equals: focusValue)
        } else {
            nativeField
        }
    }

    private var nativeField: some View {
        // The handler goes through `handle`, which outlives this render, so it never acts on a
        // stale editor.
        let handle = handle
        return NativeMarkdownField(
            text: $text,
            placeholder: placeholder,
            minHeight: minHeight,
            maxHeight: maxHeight,
            isFocused: focus.map { $0.wrappedValue == focusValue },
            onFocusChange: focusChangeHandler,
            onReturn: onReturn,
            handle: handle
        )
        .onKeyPress(.return, phases: .down) { press in
            handle.controller?.handleReturnKey(modifiers: press.modifiers) ?? .ignored
        }
    }

    private var focusChangeHandler: ((Bool) -> Void)? {
        guard let focus, let focusValue else { return nil }
        return { focused in
            if focused {
                if focus.wrappedValue != focusValue { focus.wrappedValue = focusValue }
            } else {
                // Checked a turn later: when SwiftUI moves focus elsewhere, the binding still reads
                // this field while the text view resigns, and clearing it then would undo the move.
                DispatchQueue.main.async {
                    if focus.wrappedValue == focusValue { focus.wrappedValue = nil }
                }
            }
        }
    }
}

extension MarkdownEditor where Focus == MarkdownEditorNoFocus {
    init(
        text: Binding<String>,
        placeholder: String = "",
        minHeight: CGFloat = 20,
        maxHeight: CGFloat? = nil,
        showSlackControls: Bool = true,
        copyHelp: String = "Copy for Slack"
    ) {
        self._text = text
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.showSlackControls = showSlackControls
        self.copyHelp = copyHelp
        self.focus = nil
        self.focusValue = nil
        self.onReturn = nil
    }
}

struct MarkdownSlackControls: View {
    var copyHelp = "Copy for Slack"
    let copy: () -> Void
    let paste: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Spacer()
            Button(action: copy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help(copyHelp)

            Button(action: paste) {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.plain)
            .help("Paste from Slack, converting to markdown")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Slack's composer inserts pasted plain text verbatim and parses only the HTML flavour, so
/// formatting travels as HTML. The plain flavour is the raw markdown, which suits every other
/// paste target (GitHub, Notion, a terminal).
func copyMarkdownForSlack(_ markdown: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.declareTypes([.html, .string], owner: nil)
    pasteboard.setString(#"<meta charset="utf-8">"# + markdownToSlackHTML(markdown), forType: .html)
    pasteboard.setString(markdown, forType: .string)
}
