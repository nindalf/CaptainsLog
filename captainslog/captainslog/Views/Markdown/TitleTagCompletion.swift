import AppKit
import SwiftData
import SwiftUI

extension View {
    /// `.focused(_:equals:)` plus `@` / `#` completion while focused, for a single-line
    /// `TextField`. SwiftUI's field keeps its own focus, submit and Tab handling; completion works
    /// through the window's field editor, which is the text view a focused `TextField` types into.
    func focusedWithTagCompletion<Value: Hashable>(_ binding: FocusState<Value?>.Binding, equals value: Value) -> some View {
        focused(binding, equals: value)
            .modifier(TagCompletionModifier(isActive: binding.wrappedValue == value))
    }
}

private struct TagCompletionModifier: ViewModifier {
    let isActive: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var completion = FieldEditorTagCompletion()

    func body(content: Content) -> some View {
        content
            .background(WindowReporter { completion.window = $0 })
            .onChange(of: isActive, initial: true) {
                if isActive { completion.activate(modelContext: modelContext) } else { completion.deactivate() }
            }
            .onDisappear { completion.deactivate() }
    }
}

/// Follows the field editor's edits while the field is active. The field editor is shared by
/// every text field in the window, so each notification is checked against the window and the
/// first responder before it counts.
private final class FieldEditorTagCompletion {
    weak var window: NSWindow?
    private let completer = TagCompleter()
    private var observers: [NSObjectProtocol] = []

    deinit {
        removeObservers()
    }

    func activate(modelContext: ModelContext) {
        completer.modelContext = modelContext
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSText.didChangeNotification, object: nil, queue: nil) { [weak self] note in
            MainActor.assumeIsolated {
                guard let textView = self?.fieldEditor(note), Self.typed(NSApp.currentEvent, into: textView) else { return }
                textView.joinTagBeforeCaret()
            }
        })
        observers.append(center.addObserver(forName: NSTextView.didChangeSelectionNotification, object: nil, queue: nil) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let textView = self.fieldEditor(note) else { return }
                self.completer.textView = textView
                self.completer.update()
            }
        })
    }

    func deactivate() {
        removeObservers()
        completer.end()
    }

    private func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    private func fieldEditor(_ note: Notification) -> NSTextView? {
        guard let textView = note.object as? NSTextView, textView.isFieldEditor,
              let window, textView.window === window, window.firstResponder === textView else { return nil }
        return textView
    }

    /// A join should follow typed text only, so Delete, undo (Cmd-Z) and paste don't trigger one:
    /// the key's characters must be what now ends the text before the caret.
    private static func typed(_ event: NSEvent?, into textView: NSTextView) -> Bool {
        guard let event, event.type == .keyDown, event.modifierFlags.intersection([.command, .control]).isEmpty,
              let characters = event.characters, !characters.isEmpty else { return false }
        return textView.lineTextBefore(textView.selectedRange().location).hasSuffix(characters)
    }
}

/// Reports the window a view lands in.
private struct WindowReporter: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: ReportingView, context: Context) {
        view.onWindow = onWindow
    }

    final class ReportingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
