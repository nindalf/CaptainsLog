import SwiftUI
import CaptainsLogKit

/// A logbook row: completion date, title, project subtitle, notes and source icons.
struct CompletedTodoRowView: View {
    let todo: Todo
    let isSelected: Bool
    /// Off inside a project, where the header already names it.
    var showsProject: Bool = true
    var onSelect: () -> Void
    var onExpand: () -> Void
    var onComplete: () -> Void

    private var dateLabel: String {
        guard let date = todo.completedDate else { return "" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    var body: some View {
        HStack(spacing: 10) {
            TodoCheckbox(todo: todo, onComplete: onComplete)

            HStack(spacing: 12) {
                Text(dateLabel)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 46, alignment: .trailing)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(todo.title)
                            .lineLimit(1)
                        TodoTitleBadges(todo: todo)
                    }
                    if showsProject, let project = todo.project {
                        Text(project.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                // Cmd- and Shift-clicks change the selection rather than opening the row.
                let extending = !NSEvent.modifierFlags.intersection([.command, .shift]).isEmpty
                if isSelected && !extending {
                    onExpand()
                } else {
                    onSelect()
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
    }
}
