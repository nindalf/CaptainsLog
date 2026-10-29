import SwiftUI
import CaptainsLogKit

enum FeedItemType: String, CaseIterable, Identifiable {
    case log = "Log"
    case meeting = "Meeting"
    case interview = "Interview"
    case pullRequest = "PR"
    case todo = "Todo"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .log: "book"
        case .meeting: "calendar"
        case .interview: "person.badge.clock"
        case .pullRequest: "arrow.triangle.pull"
        case .todo: "checkmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .log: .blue
        case .meeting: .green
        case .interview: .orange
        case .pullRequest: .purple
        case .todo: .teal
        }
    }
}

enum FeedItem: Identifiable {
    case log(LogEntry)
    case meeting(Meeting)
    case interview(Interview)
    case pullRequest(PullRequest)
    case todo(Todo)

    var id: UUID {
        switch self {
        case .log(let e): e.id
        case .meeting(let m): m.id
        case .interview(let i): i.id
        case .pullRequest(let pr): pr.id
        case .todo(let t): t.id
        }
    }

    var timestamp: Date {
        switch self {
        case .log(let e): e.timestamp
        case .meeting(let m): m.date
        case .interview(let i): i.date
        case .pullRequest(let pr): Feed.date(of: pr)
        case .todo(let t): Feed.date(of: t)
        }
    }

    var title: String {
        switch self {
        case .log(let e): e.title
        case .meeting(let m): m.title
        case .interview(let i): i.candidateName
        case .pullRequest(let pr): pr.title
        case .todo(let t): t.title
        }
    }

    var itemType: FeedItemType {
        switch self {
        case .log: .log
        case .meeting: .meeting
        case .interview: .interview
        case .pullRequest: .pullRequest
        case .todo: .todo
        }
    }
}

struct FeedDateGroup: Identifiable {
    let date: Date
    let items: [FeedItem]

    var id: Date { date }

    var label: String {
        DateLabel.header(date)
    }

    static func group(_ items: [FeedItem]) -> [FeedDateGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
            cal.startOfDay(for: item.timestamp)
        }
        return grouped.keys.sorted(by: >).map { day in
            FeedDateGroup(
                date: day,
                items: grouped[day]!.sorted { $0.timestamp > $1.timestamp }
            )
        }
    }
}
