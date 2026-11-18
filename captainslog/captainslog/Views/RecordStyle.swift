import SwiftUI
import CaptainsLogKit

/// One icon and one colour per kind of record, the same wherever the record appears: the Log,
/// Search, the tabs, people's pages, the calendar and the sidebar.
enum RecordKind {
    case todo, pullRequest, meeting, interview, log, person, project, feedback

    var icon: String {
        switch self {
        case .todo: "checkmark.circle"
        case .pullRequest: "arrow.triangle.merge"
        case .meeting: "calendar"
        case .interview: "person.badge.clock"
        case .log: "book"
        case .person: "person.crop.circle"
        case .project: "folder"
        case .feedback: "text.bubble"
        }
    }

    var color: Color {
        switch self {
        case .todo: .teal
        case .pullRequest: .purple
        case .meeting: .green
        case .interview: .orange
        case .log: .blue
        case .person: .indigo
        case .project: .cyan
        case .feedback: .pink
        }
    }
}

/// A record's icon at the head of its row.
struct RecordIcon: View {
    let kind: RecordKind

    var body: some View {
        Image(systemName: kind.icon)
            .font(.system(size: 12))
            .foregroundStyle(kind.color)
            .frame(width: RecordRowMetrics.iconWidth)
    }
}

enum RecordRowMetrics {
    static let iconWidth: CGFloat = 20
    static let padding: CGFloat = 12
    static let spacing: CGFloat = 10
    /// Where the title starts, for a card that lines its details up under it.
    static let titleInset = padding + iconWidth + spacing
}

/// The one list row: the record's icon, its title over a secondary line, and on the right the date
/// the list needs over a badge.
struct RecordRow<Leading: View, Title: View, Secondary: View, Trailing: View>: View {
    var isSelected = false
    /// Off inside a `DetailSection` box, which pads its rows itself.
    var isPadded = true
    @ViewBuilder var leading: Leading
    @ViewBuilder var title: Title
    @ViewBuilder var secondary: Secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: RecordRowMetrics.spacing) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.headline)
                    .lineLimit(1)
                secondary
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                trailing
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: isPadded ? 44 : 32, alignment: .leading)
        .padding(.horizontal, isPadded ? RecordRowMetrics.padding : 0)
        .padding(.vertical, isPadded ? 4 : 0)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

/// The date in a row's right-hand slot, in whatever form the list needs.
enum RowDate {
    /// "14:30", in a list grouped by day.
    case time(Date)
    /// "Today", "21 Oct".
    case day(Date)
    /// "Today 14:30".
    case dayTime(Date)
    /// "40m", "2h", "3d" ago.
    case age(Date)
    case none

    var text: String? {
        switch self {
        case .time(let date): date.formatted(.dateTime.hour().minute())
        case .day(let date): DateLabel.day(date)
        case .dayTime(let date): DateLabel.dayTime(date)
        case .age(let date): Self.age(since: date)
        case .none: nil
        }
    }

    static func age(since date: Date) -> String {
        let minutes = Int(Date.now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h" }
        return "\(minutes / (24 * 60))d"
    }
}

/// An interview's recommendation, the same capsule everywhere.
struct VerdictBadge: View {
    let recommendation: Recommendation

    var body: some View {
        Text(recommendation.label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(recommendation.color.opacity(0.2), in: .capsule)
            .foregroundStyle(recommendation.color)
    }
}

extension Recommendation {
    /// In the order a picker lists them, best first.
    static let ranked: [Recommendation] = [.strongYes, .yes, .no, .definitelyNot]

    var label: String {
        switch self {
        case .strongYes: "Strong yes"
        case .yes: "Yes"
        case .no: "No"
        case .definitelyNot: "Definitely not"
        }
    }

    var color: Color {
        switch self {
        case .strongYes, .yes: .green
        case .no: .orange
        case .definitelyNot: .red
        }
    }
}

/// A grey capsule for a plain label in a row's badge slot, such as a log entry's source.
struct TagBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: .capsule)
    }
}

// MARK: - Rows per kind

struct PRRecordRow: View {
    let pr: PullRequest
    var attention: PRAttention?
    var date: RowDate
    var isSelected = false
    var isPadded = true

    var body: some View {
        let attention = attention ?? pr.attention()
        RecordRow(isSelected: isSelected, isPadded: isPadded) {
            RecordIcon(kind: .pullRequest)
        } title: {
            Text(pr.title)
        } secondary: {
            PRSecondaryLine(pr: pr, attention: attention)
        } trailing: {
            if let text = date.text { Text(text) }
            PRSizeBar(additions: pr.additions, deletions: pr.deletions)
                .frame(height: 12)
        }
    }
}

/// Who wrote it, its number, and why it's where it is, coloured only when it needs me.
struct PRSecondaryLine: View {
    let pr: PullRequest
    let attention: PRAttention

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: [pr.isAuthoredByMe ? "you" : pr.author?.name, "#\(pr.number)"]
                .compactMap { $0 }.joined(separator: " · "))
            if let reason = attention.reason(pr) {
                Text(verbatim: " · ")
                HStack(spacing: 3) {
                    Text(reason)
                    if attention.isStale {
                        Image(systemName: "exclamationmark.triangle.fill").imageScale(.small)
                    }
                }
                .foregroundStyle(attention.tint ?? AnyShapeStyle(.secondary))
                .help(attention.isStale ? "No review for \(PRAttention.staleAfterWorkingDays) working days" : "")
            }
        }
    }
}

struct InterviewRecordRow: View {
    let interview: Interview
    var date: RowDate
    var isSelected = false
    var isPadded = true

    var body: some View {
        RecordRow(isSelected: isSelected, isPadded: isPadded) {
            RecordIcon(kind: .interview)
        } title: {
            Text(interview.candidateName)
        } secondary: {
            Text([interview.role, interview.coInterviewer.map { "with \($0.name)" }]
                .compactMap { $0 }.joined(separator: " · "))
        } trailing: {
            if let text = date.text { Text(text) }
            if let recommendation = interview.recommendation {
                VerdictBadge(recommendation: recommendation)
            }
        }
    }
}

struct MeetingRecordRow: View {
    let meeting: Meeting
    var date: RowDate
    var isSelected = false
    var isPadded = true

    var body: some View {
        RecordRow(isSelected: isSelected, isPadded: isPadded) {
            RecordIcon(kind: .meeting)
        } title: {
            Text(meeting.title)
        } secondary: {
            let attendees = meeting.attendees.count
            Text([
                attendees > 0 ? "\(attendees) attendee\(attendees == 1 ? "" : "s")" : nil,
                meeting.notes != nil || meeting.summary != nil ? "has notes" : nil,
            ].compactMap { $0 }.joined(separator: " · "))
        } trailing: {
            if let text = date.text { Text(text) }
        }
    }
}

struct LogRecordRow: View {
    let entry: LogEntry
    var date: RowDate
    var isSelected = false
    var isPadded = true

    var body: some View {
        RecordRow(isSelected: isSelected, isPadded: isPadded) {
            RecordIcon(kind: .log)
        } title: {
            Text(entry.title)
        } secondary: {
            if !entry.content.isEmpty {
                Text(markdownPreview(entry.content))
            }
        } trailing: {
            if let text = date.text { Text(text) }
            // Manual is the default; only the other sources say anything.
            if entry.source != .manual {
                TagBadge(text: entry.source.rawValue)
            }
        }
    }
}

extension PRAttention {
    /// The colour of what a PR needs from me, nil where it needs nothing.
    var tint: AnyShapeStyle? {
        switch self {
        case .conflict, .changesRequested, .approvalDismissed: AnyShapeStyle(.orange)
        case .ciFailing: AnyShapeStyle(.red)
        case .readyToMerge: AnyShapeStyle(.green)
        case .reviewRequested, .reReview: AnyShapeStyle(.blue)
        default: isStale ? AnyShapeStyle(.orange) : nil
        }
    }
}
