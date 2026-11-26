import SwiftUI
import CaptainsLogKit

/// One icon and one colour per kind of record, the same wherever the record appears. The sidebar
/// uses the icons.
enum RecordKind {
    case todo, pullRequest, meeting, interview, log, person, project, feedback

    var icon: String {
        switch self {
        case .todo: "checkmark.circle"
        case .pullRequest: "arrow.triangle.pull"
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

/// The parts present, joined as a row's secondary line, or nil when none are.
func joinedLine(_ parts: String?...) -> String? {
    let present = parts.compactMap { $0 }.filter { !$0.isEmpty }
    return present.isEmpty ? nil : present.joined(separator: " · ")
}

extension CalendarEvent {
    /// An interview's or meeting's colour; grey for an event with neither.
    var recordColor: Color {
        if interview != nil { return RecordKind.interview.color }
        if meeting != nil { return RecordKind.meeting.color }
        return .gray
    }
}

extension View {
    /// The card a one-line record expands into in place: raised off the list by a border and a
    /// shadow, so edit mode is plain to see.
    func recordCard() -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
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
    /// Two for a search result's match, which one line can cut off.
    var secondaryLineLimit = 1
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
                    .lineLimit(secondaryLineLimit)
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
        .selectionHighlight(isSelected)
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

    var text: String {
        switch self {
        case .time(let date): date.formatted(.dateTime.hour().minute())
        case .day(let date): DateLabel.day(date)
        case .dayTime(let date): DateLabel.dayTime(date)
        case .age(let date): Self.age(since: date)
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

/// A small icon after a title that stands for a linked record or a property, in the record's colour,
/// with a tooltip saying what it is. With an action, a click opens what it stands for.
struct RecordBadge: View {
    let icon: String
    var color: Color?
    let help: String
    var action: (() -> Void)?

    init(_ kind: RecordKind, help: String, action: (() -> Void)? = nil) {
        self.icon = kind.icon
        self.color = kind.color
        self.help = help
        self.action = action
    }

    init(icon: String, help: String) {
        self.icon = icon
        self.help = help
    }

    var body: some View {
        let image = Image(systemName: icon)
            .font(.caption)
            .foregroundStyle(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            .contentShape(.rect)
        Group {
            if let action {
                Button(action: action) { image }
                    .buttonStyle(.plain)
            } else {
                image
            }
        }
        .help(help)
        .accessibilityLabel(help)
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
            if let line = joinedLine(interview.role, interview.coInterviewer.map { "with \($0.name)" }) {
                Text(line)
            }
        } trailing: {
            Text(date.text)
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
            let hasNotes = meeting.notes != nil || meeting.summary != nil
            HStack(spacing: 0) {
                if attendees > 0 { Text("^[\(attendees) attendee](inflect: true)") }
                if attendees > 0 && hasNotes { Text(verbatim: " · ") }
                if hasNotes { Text("has notes") }
            }
        } trailing: {
            Text(date.text)
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
            Text(date.text)
            // Manual is the default; only the other sources say anything.
            if entry.source != .manual {
                TagBadge(text: entry.source.rawValue)
            }
        }
    }
}

/// Feedback has no title, so its first line stands in for one, the rest below it.
struct FeedbackRecordRow: View {
    let feedback: Feedback
    var date: RowDate
    var isSelected = false
    var isPadded = true

    private var lines: (first: String, rest: String) {
        let trimmed = feedback.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let newline = trimmed.firstIndex(where: \.isNewline) else { return (trimmed, "") }
        return (String(trimmed[..<newline]), String(trimmed[newline...]))
    }

    var body: some View {
        let lines = lines
        RecordRow(isSelected: isSelected, isPadded: isPadded) {
            RecordIcon(kind: .feedback)
        } title: {
            if lines.first.isEmpty {
                Text("No content").foregroundStyle(.tertiary)
            } else {
                Text(markdownPreview(lines.first))
            }
        } secondary: {
            if !lines.rest.isEmpty {
                Text(markdownPreview(lines.rest))
            }
        } trailing: {
            Text(date.text)
        }
    }
}
