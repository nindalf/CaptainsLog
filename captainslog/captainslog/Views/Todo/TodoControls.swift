import SwiftUI
import CaptainsLogKit

/// A todo's controls, at the bottom right of its card and of Quick Entry: project, When, privacy,
/// then the trash where there is one. A set project or When shows as a pill, else as an icon.
struct TodoControls: View {
    @Bindable var todo: Todo
    let projects: [Project]
    /// Quick Entry keeps its project here until Save, since relating a draft inserts it.
    var pendingProject: Binding<UUID?>? = nil
    var onDelete: (() -> Void)? = nil

    @State private var showWhen = false
    @State private var showProject = false

    private var project: Project? {
        guard let pendingProject else { return todo.project }
        return projects.first { $0.id == pendingProject.wrappedValue }
    }

    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            projectControl
            whenControl
            PrivacyEye(isOn: $todo.isPrivate)
            if let onDelete {
                CardTrashButton(help: "Move to Trash", action: onDelete)
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
    }

    private var projectControl: some View {
        Button { showProject.toggle() } label: {
            if let project {
                Text(project.name).cardPill(.blue)
            } else {
                Image(systemName: "list.bullet")
            }
        }
        .buttonStyle(.plain)
        .help("Project")
        .popover(isPresented: $showProject) {
            if let pendingProject {
                TodoProjectPopover(current: project, projects: projects) { pendingProject.wrappedValue = $0?.id }
            } else {
                TodoProjectPopover(todo: todo, projects: projects)
            }
        }
    }

    private var whenControl: some View {
        Button { showWhen.toggle() } label: {
            if let due = todo.dueDate {
                let overdue = Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: .now)
                Text(DateLabel.day(due)).cardPill(overdue ? .red : .blue)
            } else if todo.schedule == .someday {
                Label("Someday", systemImage: SmartList.someday.systemImage).cardPill(SmartList.someday.tint)
            } else {
                Image(systemName: "calendar")
            }
        }
        .buttonStyle(.plain)
        .help("When")
        .popover(isPresented: $showWhen) { TodoWhenPopover(todos: [todo]) }
    }
}
