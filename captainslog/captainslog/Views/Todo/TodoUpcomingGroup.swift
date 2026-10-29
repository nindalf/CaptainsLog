import Foundation
import CaptainsLogKit

/// Scheduled todos bucketed for the Upcoming list: one group per day for the next six days
/// (Tomorrow, then weekday names), then by month.
struct TodoUpcomingGroup: Identifiable {
    let label: String
    /// The first and last days the group holds; the same day for a day group.
    let firstDay: Date
    let lastDay: Date
    let todos: [Todo]

    var id: String { label }

    private struct Bucket: Hashable {
        let firstDay: Date
        let lastDay: Date
        let label: String
    }

    /// Days after today that get a group of their own.
    private static let dayGroupCount = 6

    static func group(_ todos: [Todo], now: Date = .now) -> [TodoUpcomingGroup] {
        let cal = Calendar.current
        let dated = todos.filter { $0.dueDate != nil }
        let grouped = Dictionary(grouping: dated) { bucket(for: $0.dueDate!, now: now, cal: cal) }
        return grouped.keys.sorted { $0.firstDay < $1.firstDay }.map { bucket in
            TodoUpcomingGroup(
                label: bucket.label,
                firstDay: bucket.firstDay,
                lastDay: bucket.lastDay,
                todos: grouped[bucket]!.sorted {
                    if $0.dueDate != $1.dueDate { return $0.dueDate! < $1.dueDate! }
                    return $0.sortOrder < $1.sortOrder
                }
            )
        }
    }

    /// Each group's heading followed by its rows, as the list lays them out.
    static func items(_ groups: [TodoUpcomingGroup]) -> [TodoListItem] {
        groups.flatMap { [TodoListItem.group($0.label)] + $0.todos.map { .todo($0.id) } }
    }

    /// The date a todo dropped at its place in `items` takes: its own if it still sorts there,
    /// else the date of the todo above it in its group, or the group's first day at the top.
    static func dueDate(for id: UUID, droppedIn items: [TodoListItem], groups: [TodoUpcomingGroup]) -> Date? {
        guard let index = items.firstIndex(of: .todo(id)) else { return nil }
        let lookup = Dictionary(uniqueKeysWithValues: groups.flatMap(\.todos).map { ($0.id, $0) })
        var label: String?
        var above: Todo?
        for item in items[..<index].reversed() {
            if case .group(let groupLabel) = item {
                label = groupLabel
                break
            }
            if above == nil, let todoID = item.todoID { above = lookup[todoID] }
        }
        var below: Todo?
        for item in items[(index + 1)...] {
            if case .group = item { break }
            if let todoID = item.todoID {
                below = lookup[todoID]
                break
            }
        }
        guard let label, let group = groups.first(where: { $0.label == label }) else { return nil }
        let lower = above?.dueDate ?? group.firstDay
        let upper = below?.dueDate ?? group.lastDay
        if let own = lookup[id]?.dueDate, lower <= own, own <= upper { return own }
        return lower
    }

    private static func bucket(for date: Date, now: Date, cal: Calendar) -> Bucket {
        let day = cal.startOfDay(for: date)
        let offset = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: day).day ?? 0
        switch offset {
        case ...0:
            return Bucket(firstDay: day, lastDay: day, label: "Today")
        case 1...dayGroupCount:
            return Bucket(firstDay: day, lastDay: day, label: DateLabel.header(date, now: now, calendar: cal))
        default:
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? day
            let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? day
            // The rest of this month starts after the day groups, not on the 1st.
            let afterDayGroups = cal.date(byAdding: .day, value: dayGroupCount + 1, to: cal.startOfDay(for: now)) ?? day
            let sameYear = cal.isDate(date, equalTo: now, toGranularity: .year)
            let label = sameYear
                ? date.formatted(.dateTime.month(.wide))
                : date.formatted(.dateTime.month(.wide).year())
            return Bucket(firstDay: max(monthStart, afterDayGroups), lastDay: monthEnd, label: label)
        }
    }
}
