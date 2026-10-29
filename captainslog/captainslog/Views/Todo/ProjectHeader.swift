import SwiftUI
import SwiftData
import CaptainsLogKit

/// Top of a project's todo list: icon, editable title, notes, and Complete/Reopen.
struct ProjectHeader: View {
    @Bindable var project: Project

    @Environment(\.modelContext) private var modelContext
    @Environment(Navigator.self) private var navigator
    @Query private var allProjects: [Project]
    @Query(filter: #Predicate<Todo> { $0.completedDate == nil }) private var openTodos: [Todo]

    @State private var nameDraft = ""
    @State private var nameError: String?
    @State private var confirmCompletion = false
    @State private var showIconPicker = false
    @FocusState private var titleFocused: Bool

    private var remainingTodos: [Todo] {
        openTodos.filter { !$0.isTrashed && $0.project?.id == project.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button { showIconPicker = true } label: {
                    Image(systemName: project.icon)
                        .font(.title2)
                        .foregroundStyle(project.isCompleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.blue))
                }
                .buttonStyle(.plain)
                .help("Choose Icon")
                .popover(isPresented: $showIconPicker) {
                    ProjectIconPicker(project: project) { try? modelContext.save() }
                }
                TextField("Project Name", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                    .focused($titleFocused)
                    .onSubmit(commitName)
                    .onChange(of: titleFocused) { _, focused in
                        if focused { nameError = nil } else { commitName() }
                    }
                completionButton
            }
            if let nameError {
                Text(nameError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            MarkdownEditor(
                text: Binding(
                    get: { project.notes ?? "" },
                    set: { project.notes = $0.isEmpty ? nil : $0 }
                ),
                placeholder: "Notes",
                minHeight: 20,
                maxHeight: 200,
                showSlackControls: false
            )
            // Size to the notes rather than taking all the height on offer, which pushed the todos down.
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .task(id: project.id) {
            nameDraft = project.name
            nameError = nil
            if navigator.renamingProjectID == project.id {
                navigator.renamingProjectID = nil
                // Focus set in the same pass as the field appears is dropped.
                try? await Task.sleep(for: .milliseconds(100))
                titleFocused = true
            }
        }
        .alert("Complete \"\(project.name)\"?", isPresented: $confirmCompletion) {
            Button("Complete") { complete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let remaining = remainingTodos.count
            Text("Its \(remaining) remaining \(remaining == 1 ? "to-do" : "to-dos") will be completed too.")
        }
    }

    @ViewBuilder
    private var completionButton: some View {
        if project.isCompleted {
            Button("Reopen") {
                ProjectCompletion.reopen(project)
                try? modelContext.save()
            }
        } else {
            Button("Complete") {
                if remainingTodos.isEmpty { complete() } else { confirmCompletion = true }
            }
        }
    }

    private func complete() {
        ProjectCompletion.complete(project, openTodos: remainingTodos)
        try? modelContext.save()
    }

    /// Renames only to a non-empty name no other project has: a clash would upsert over that project.
    private func commitName() {
        guard nameDraft != project.name else { return }
        if let name = ProjectNaming.validated(nameDraft, for: project, among: allProjects) {
            project.name = name
            nameDraft = name
            nameError = nil
            try? modelContext.save()
        } else {
            let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            nameError = trimmed.isEmpty
                ? "A project needs a name."
                : "There is already a project called \"\(trimmed)\"."
            nameDraft = project.name
        }
    }
}
