import SwiftUI
import CaptainsLogKit

/// Things' When popover: Today, Tomorrow, a month calendar, then Someday. The todos' current When is
/// highlighted, and Clear appears once one is set. A choice applies to every todo given.
struct TodoWhenPopover: View {
    let todos: [Todo]
    /// Called after a choice is applied, for the host to save.
    var onChoose: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    /// First day of the month the calendar shows.
    @State private var month: Date

    private let calendar = Calendar.current

    init(todos: [Todo], onChoose: @escaping () -> Void = {}) {
        self.todos = todos
        self.onChoose = onChoose
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var shown = today
        if case .day(let date)? = TodoWhen.common(to: todos, calendar: cal), date > today { shown = date }
        _month = State(initialValue: cal.dateInterval(of: .month, for: shown)?.start ?? today)
    }

    private var current: TodoWhen? { TodoWhen.common(to: todos, calendar: calendar) }
    private var today: Date { calendar.startOfDay(for: .now) }
    private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: today) ?? today }

    private var selectedDay: Date? {
        if case .day(let date)? = current { return date }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            choiceRow("Today", systemImage: "star.fill", tint: .yellow, when: .day(today))
            choiceRow("Tomorrow", systemImage: "sunrise.fill", tint: .orange, when: .day(tomorrow))
            MonthGrid(month: $month, selected: selectedDay, today: today, allowsPast: false) { choose(.day($0)) }
                .padding(.vertical, 6)
            choiceRow("Someday", systemImage: SmartList.someday.systemImage, tint: SmartList.someday.tint, when: .someday)
            if todos.contains(where: { TodoWhen.of($0, calendar: calendar) != .unset }) {
                Divider()
                    .padding(.vertical, 4)
                Button { choose(.unset) } label: {
                    Text("Clear")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: 250)
    }

    private func choiceRow(_ title: String, systemImage: String, tint: Color, when: TodoWhen) -> some View {
        Button { choose(when) } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(current == when ? Color.accentColor.opacity(0.25) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ when: TodoWhen) {
        for todo in todos {
            when.apply(to: todo, calendar: calendar)
        }
        onChoose()
        dismiss()
    }
}
