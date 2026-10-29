import SwiftUI
import AppKit

extension View {
    /// AppKit selects all of a text field it focuses, so opening a card would leave the first key
    /// replacing the title. The caret goes to the end instead; a click's own caret is left alone.
    func caretAtEndWhenFocused(_ isFocused: Bool) -> some View {
        onChange(of: isFocused, initial: true) { _, focused in
            // After AppKit has focused the field and selected it.
            if focused { DispatchQueue.main.async(execute: moveCaretToEnd) }
        }
    }
}

@MainActor
private func moveCaretToEnd() {
    guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor else { return }
    let length = editor.string.utf16.count
    guard length > 0, editor.selectedRange() == NSRange(location: 0, length: length) else { return }
    editor.setSelectedRange(NSRange(location: length, length: 0))
}
