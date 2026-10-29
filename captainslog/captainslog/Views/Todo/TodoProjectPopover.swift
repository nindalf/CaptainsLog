import SwiftUI
import CaptainsLogKit

struct TodoProjectPopover: View {
    let current: Project?
    let projects: [Project]
    let onPick: (Project?) -> Void
    @Environment(\.dismiss) private var dismiss

    init(todo: Todo, projects: [Project]) {
        self.init(current: todo.project, projects: projects) { todo.project = $0 }
    }

    /// For a todo that isn't saved yet, which mustn't be related to a project until it is.
    init(current: Project?, projects: [Project], onPick: @escaping (Project?) -> Void) {
        self.current = current
        self.projects = projects
        self.onPick = onPick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                onPick(nil)
                dismiss()
            } label: {
                HStack {
                    Text("No Project")
                    Spacer()
                    if current == nil {
                        Image(systemName: "checkmark").foregroundStyle(.blue)
                    }
                }
            }
            .buttonStyle(.plain)

            Divider()

            // Completed projects are hidden unless this todo is already in one.
            ForEach(projects.filter { !$0.isCompleted || $0.id == current?.id }) { project in
                Button {
                    onPick(project)
                    dismiss()
                } label: {
                    HStack {
                        Text(project.name)
                        Spacer()
                        if current?.id == project.id {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 200)
    }
}
