import SwiftUI
import SwiftData
import CaptainsLogKit

/// A completed todo opened in the Log: laid out like a log entry's card, with a todo card's controls.
struct CompletedTodoCardView: View {
    @Bindable var todo: Todo
    let projects: [Project]
    var focusedField: FocusState<LogFocusField?>.Binding
    var onCollapse: () -> Void

    private var notesBinding: Binding<String> {
        Binding(
            get: { todo.notes ?? "" },
            set: { todo.notes = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $todo.title.skippingNoOps)
                .textFieldStyle(.plain)
                .font(.body)
                .focusedWithTagCompletion(focusedField, equals: .title(todo.id))
                .caretAtEndWhenFocused(focusedField.wrappedValue == .title(todo.id))
                .onSubmit { focusedField.wrappedValue = .content(todo.id) }

            MarkdownEditor(
                text: notesBinding,
                placeholder: "Notes",
                minHeight: 40,
                maxHeight: 200,
                showSlackControls: false,
                focus: focusedField,
                focusValue: .content(todo.id),
                onReturn: onCollapse
            )

            HStack {
                if let completed = todo.completedDate {
                    Text("Completed \(completed, format: .dateTime.day().month(.abbreviated).hour().minute())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TodoControls(todo: todo, projects: projects)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { }
        // On close rather than per keystroke, as todo cards do.
        .onDisappear {
            guard let context = todo.modelContext, (try? todo.linkMentionedPeople(in: context)) == true else { return }
            try? context.save()
        }
    }
}
