import SwiftUI
import SwiftData
import CaptainsLogKit

/// A Log row: the shared row for each kind, with the time on the right.
struct FeedRowView: View {
    let item: FeedItem
    let isSelected: Bool
    /// Turns a todo's icon into a checkbox that reopens it.
    var onReopen: (() -> Void)? = nil

    var body: some View {
        let date = RowDate.time(item.timestamp)
        switch item {
        case .log(let entry):
            LogRecordRow(entry: entry, date: date, isSelected: isSelected)
        case .meeting(let meeting):
            MeetingRecordRow(meeting: meeting, date: date, isSelected: isSelected)
        case .interview(let interview):
            InterviewRecordRow(interview: interview, date: date, isSelected: isSelected)
        case .pullRequest(let pr):
            PRRecordRow(pr: pr, date: date, isSelected: isSelected)
        case .todo(let todo):
            RecordRow(isSelected: isSelected) {
                todoIcon
            } title: {
                Text(todo.title)
            } secondary: {
                if let project = todo.project { Text(project.name) }
            } trailing: {
                Text(date.text)
            }
        }
    }

    @ViewBuilder
    private var todoIcon: some View {
        if let onReopen {
            Button(action: onReopen) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(RecordKind.todo.color)
                    .frame(width: RecordRowMetrics.iconWidth, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reopen")
        } else {
            RecordIcon(kind: .todo)
        }
    }
}

#Preview("Log Entry") {
    FeedRowView(item: .log(PreviewData.makeLogEntry()), isSelected: false)
        .modelContainer(PreviewData.container)
}

#Preview("Meeting") {
    FeedRowView(item: .meeting(PreviewData.makeMeeting()), isSelected: true)
        .modelContainer(PreviewData.container)
}

#Preview("Pull Request") {
    FeedRowView(item: .pullRequest(PreviewData.makePR()), isSelected: false)
        .modelContainer(PreviewData.container)
}

#Preview("Interview") {
    FeedRowView(item: .interview(PreviewData.makeInterview()), isSelected: false)
        .modelContainer(PreviewData.container)
}

#Preview("Todo") {
    FeedRowView(item: .todo(PreviewData.makeTodo(isCompleted: true)), isSelected: false)
        .modelContainer(PreviewData.container)
}
