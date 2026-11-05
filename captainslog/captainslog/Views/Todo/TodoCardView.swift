import SwiftUI
import SwiftData
import CaptainsLogKit

struct TodoCardView: View {
    @Bindable var todo: Todo
    let projects: [Project]
    var focusedField: FocusState<TodoFocusField?>.Binding
    var onComplete: () -> Void
    var onCollapse: () -> Void = {}

    private var notesBinding: Binding<String> {
        Binding(
            get: { todo.notes ?? "" },
            set: { todo.notes = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TodoCheckbox(todo: todo, onComplete: onComplete)
                TextField("New To-Do", text: $todo.title)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focusedWithTagCompletion(focusedField, equals: .title(todo.id))
                    .onSubmit { focusedField.wrappedValue = .notes(todo.id) }
                    .caretAtEndWhenFocused(focusedField.wrappedValue == .title(todo.id))
            }
            notesEditor
            TodoControls(todo: todo, projects: projects)
                .padding(.leading, 30)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { }
        // On close rather than per keystroke, so a todo doesn't leave a meeting's or person's list
        // while its tag is being edited. A draft is still uninserted here unless it was committed.
        .onDisappear {
            guard let context = todo.modelContext, (try? todo.linkMentionedPeople(in: context)) == true else { return }
            try? context.save()
        }
    }

    private var notesEditor: some View {
        MarkdownEditor(
            text: notesBinding,
            placeholder: "Notes",
            minHeight: 20,
            maxHeight: 160,
            showSlackControls: false,
            focus: focusedField,
            focusValue: .notes(todo.id),
            onReturn: onCollapse
        )
        .padding(.leading, 30)
    }
}

#Preview {
    @Previewable @FocusState var focus: TodoFocusField?
    TodoCardView(
        todo: PreviewData.makeTodo(),
        projects: [],
        focusedField: $focus,
        onComplete: {},
        onCollapse: {}
    )
    .modelContainer(PreviewData.container)
    .padding()
}
