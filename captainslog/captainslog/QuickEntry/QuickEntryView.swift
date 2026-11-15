import SwiftUI
import SwiftData
import CaptainsLogKit

/// Things' Quick Entry: title, notes and a todo card's controls (project, When, privacy).
struct QuickEntryView: View {
    var onClose: () -> Void
    /// The content's height, for the panel to size itself to.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    static let width: CGFloat = 560

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Todo> { $0.completedDate == nil }) private var openTodos: [Todo]
    @Query(filter: #Predicate<Project> { $0.completedDate == nil }, sort: \Project.sortOrder) private var projects: [Project]

    /// Uninserted until Save, and never related to a project before then (that would insert it),
    /// so Cancel leaves nothing behind. The project waits in `projectID`.
    @State private var draft: Todo = {
        let todo = Todo(title: "")
        SmartList.inbox.move(todo)
        return todo
    }()
    @State private var projectID: UUID?
    @FocusState private var focus: TodoFocusField?

    private var project: Project? { projects.first { $0.id == projectID } }

    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    private var notesBinding: Binding<String> {
        Binding(
            get: { draft.notes ?? "" },
            set: { draft.notes = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        QuickEntryCard(canSave: canSave, onSave: save, onClose: onClose, onHeightChange: onHeightChange) {
            entry
        }
        .task { focus = .title(draft.id) }
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "square")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.secondary.opacity(0.6))
                TextField("New To-Do", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focusedWithTagCompletion($focus, equals: .title(draft.id))
                    .onSubmit(save)
            }
            MarkdownEditor(
                text: notesBinding,
                placeholder: "Notes",
                minHeight: 44,
                maxHeight: 220,
                showSlackControls: false,
                focus: $focus,
                focusValue: .notes(draft.id)
            )
            .padding(.leading, 30)
            TodoControls(todo: draft, projects: projects, pendingProject: $projectID)
                .padding(.leading, 30)
        }
    }

    private func save() {
        let title = draft.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        draft.title = title
        draft.sortOrder = TodoOrdering.topSortOrder(among: openTodos)
        modelContext.insert(draft)
        draft.project = project
        _ = try? draft.linkMentionedPeople(in: modelContext)
        try? modelContext.save()
        onClose()
    }
}

/// Quick Entry's card: an entry above Cancel and Save. Return in the entry's title or Cmd-Return
/// saves; Escape cancels.
struct QuickEntryCard<Entry: View>: View {
    var canSave: Bool
    var onSave: () -> Void
    var onClose: () -> Void
    /// The content's height, for the panel to size itself to.
    var onHeightChange: (CGFloat) -> Void
    @ViewBuilder var entry: Entry

    private static var cornerRadius: CGFloat { 16 }

    var body: some View {
        VStack(spacing: 0) {
            entry
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)
            Divider()
            footer
        }
        .frame(width: QuickEntryView.width)
        .background(Color(nsColor: .textBackgroundColor))
        // The panel is borderless, so the card draws its own corners and edge.
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        // The notes editor keeps Escape from the panel, which cancels only from a text field.
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: onClose) {
                Text("Cancel").frame(minWidth: 60)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .keyboardShortcut(.cancelAction)
            Button(action: onSave) {
                Text("Save").frame(minWidth: 60)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSave)
        }
        .controlSize(.large)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
    }
}

#Preview {
    QuickEntryView(onClose: {})
        .modelContainer(PreviewData.container)
}
