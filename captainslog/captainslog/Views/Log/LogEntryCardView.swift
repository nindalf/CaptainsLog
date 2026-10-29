import SwiftUI
import SwiftData
import CaptainsLogKit

struct LogEntryCardView: View {
    @Bindable var entry: LogEntry
    let projects: [Project]
    var focusedField: FocusState<LogFocusField?>.Binding
    var onCollapse: () -> Void
    var onDelete: () -> Void = {}

    private var contentBinding: Binding<String> {
        Binding(
            get: { entry.content },
            set: { entry.content = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $entry.title)
                .textFieldStyle(.plain)
                .font(.body)
                .focusedWithTagCompletion(focusedField, equals: .title(entry.id))
                .caretAtEndWhenFocused(focusedField.wrappedValue == .title(entry.id))
                .onSubmit { focusedField.wrappedValue = .content(entry.id) }

            MarkdownEditor(
                text: contentBinding,
                placeholder: "Content",
                minHeight: 40,
                maxHeight: 200,
                showSlackControls: false,
                focus: focusedField,
                focusValue: .content(entry.id),
                onReturn: onCollapse
            )

            LogEntryControls(entry: entry, projects: projects, onDelete: onDelete)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { }
        // On close rather than per keystroke, as todo cards do. A draft is still uninserted here
        // unless it was committed.
        .onDisappear {
            guard let context = entry.modelContext, (try? entry.linkMentionedPeople(in: context)) == true else { return }
            try? context.save()
        }
    }
}
