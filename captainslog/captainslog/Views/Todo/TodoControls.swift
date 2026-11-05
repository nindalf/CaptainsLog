import SwiftUI
import CaptainsLogKit

/// A todo's controls, at the bottom right of its card and of Quick Entry: project, When, privacy.
/// A set project or When shows as a pill, else as an icon.
struct TodoControls: View {
    @Bindable var todo: Todo
    let projects: [Project]
    /// Quick Entry keeps its project here until Save, since relating a draft inserts it.
    var pendingProject: Binding<UUID?>? = nil

    @State private var showWhen = false

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
        }
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
    }

    private var projectControl: some View {
        ProjectControl(current: project, projects: projects) { picked in
            if let pendingProject {
                pendingProject.wrappedValue = picked?.id
            } else {
                todo.project = picked
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
