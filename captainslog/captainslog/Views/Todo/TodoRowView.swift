import SwiftUI
import CaptainsLogKit

struct TodoRowView: View {
    let todo: Todo
    let isSelected: Bool
    let isCompleting: Bool
    /// A small star before the title, as Things marks Today's todos when shown in a project.
    var showsTodayStar: Bool = false
    /// Grey text under the title, as Things shows a todo's project in smart lists.
    var subtitle: String?
    var showsSource: Bool = true
    /// Grey text at the trailing edge.
    var trailing: String?
    /// Shorter rows for a section of a detail page. The Todos tab keeps 44: its drag depends on it.
    var compact: Bool = false
    var onSelect: () -> Void
    var onExpand: () -> Void
    var onComplete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            TodoCheckbox(todo: todo, onComplete: onComplete)
                .padding(.leading, compact ? 0 : 8)

            if showsTodayStar {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                    .padding(.leading, 12)
                    .help("Today")
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(todo.title)
                        .strikethrough(todo.isCompleted || isCompleting)
                        .foregroundStyle((todo.isCompleted || isCompleting) ? .secondary : .primary)
                        .lineLimit(1)
                    TodoTitleBadges(todo: todo, showsSource: showsSource)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
                .padding(.leading, showsTodayStar ? 6 : compact ? 8 : 12)
                .padding(.trailing, 8)
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

            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 28 : 44, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
    }
}
