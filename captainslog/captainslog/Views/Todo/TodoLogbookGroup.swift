import Foundation
import CaptainsLogKit

/// A completed todo or project in the Logbook.
enum LogbookEntry: Identifiable {
    case todo(Todo)
    case project(Project)

    var id: UUID {
        switch self {
        case .todo(let todo): todo.id
        case .project(let project): project.id
        }
    }

    var completedDate: Date? {
        switch self {
        case .todo(let todo): todo.completedDate
        case .project(let project): project.completedDate
        }
    }
}

/// Completed todos and projects bucketed for the logbook: Today, Yesterday, then by month,
/// most recent first.
struct TodoLogbookGroup: Identifiable {
    let label: String
    let sortKey: Date
    let entries: [LogbookEntry]

    var id: String { label }

    var todos: [Todo] {
        entries.compactMap { if case .todo(let todo) = $0 { todo } else { nil } }
    }

    private struct Bucket: Hashable {
        let key: Date
        let label: String
    }

    static func group(_ todos: [Todo], projects: [Project] = [], now: Date = .now) -> [TodoLogbookGroup] {
        let cal = Calendar.current
        let entries = todos.map(LogbookEntry.todo) + projects.map(LogbookEntry.project)
        let grouped = Dictionary(grouping: entries) { bucket(for: $0.completedDate, now: now, cal: cal) }
        return grouped.keys.sorted { $0.key > $1.key }.map { bucket in
            TodoLogbookGroup(
                label: bucket.label,
                sortKey: bucket.key,
                entries: grouped[bucket]!.sorted {
                    ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast)
                }
            )
        }
    }

    private static func bucket(for date: Date?, now: Date, cal: Calendar) -> Bucket {
        guard let date else {
            return Bucket(key: .distantPast, label: "No Date")
        }
        if cal.isDate(date, inSameDayAs: now) {
            return Bucket(key: cal.startOfDay(for: date), label: "Today")
        }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: yesterday) {
            return Bucket(key: cal.startOfDay(for: date), label: "Yesterday")
        }
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        let sameYear = cal.isDate(date, equalTo: now, toGranularity: .year)
        let label = sameYear
            ? date.formatted(.dateTime.month(.wide))
            : date.formatted(.dateTime.month(.wide).year())
        return Bucket(key: monthStart, label: label)
    }
}
