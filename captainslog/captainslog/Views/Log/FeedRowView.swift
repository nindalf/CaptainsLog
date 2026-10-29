import SwiftUI
import SwiftData
import CaptainsLogKit

struct FeedRowView: View {
    let item: FeedItem
    let isSelected: Bool
    /// Turns a todo's icon into a checkbox that reopens it.
    var onReopen: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                subtitle
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.timestamp, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                badge
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if case .todo = item, let onReopen {
            Button(action: onReopen) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(item.itemType.color)
                    .frame(width: 20, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reopen")
        } else {
            Image(systemName: item.itemType.icon)
                .font(.system(size: 12))
                .foregroundStyle(item.itemType.color)
                .frame(width: 20)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch item {
        case .log(let entry):
            HStack(spacing: 6) {
                if !entry.content.isEmpty {
                    Text(markdownPreview(entry.content))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        case .meeting(let meeting):
            HStack(spacing: 6) {
                if !meeting.attendees.isEmpty {
                    Text("^[\(meeting.attendees.count) attendee](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if meeting.notes != nil {
                    Text("has notes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        case .interview(let interview):
            HStack(spacing: 6) {
                if let role = interview.role {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        case .pullRequest(let pr):
            HStack(spacing: 6) {
                Text("#\(pr.number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(pr.repo)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        case .todo(let todo):
            HStack(spacing: 6) {
                if let project = todo.project {
                    Text(project.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch item {
        case .log(let entry):
            // Manual is the default; only the other sources say anything.
            if entry.source != .manual {
                Text(entry.source.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        case .meeting:
            EmptyView()
        case .interview(let interview):
            if let rec = interview.recommendation {
                Text(rec.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(recommendationColor(rec).opacity(0.2))
                    .foregroundStyle(recommendationColor(rec))
                    .clipShape(Capsule())
            }
        case .pullRequest(let pr):
            Text(pr.state.rawValue)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(prStateColor(pr.state).opacity(0.2))
                .foregroundStyle(prStateColor(pr.state))
                .clipShape(Capsule())
        case .todo:
            EmptyView()
        }
    }

    private func prStateColor(_ state: PRState) -> Color {
        switch state {
        case .open: .green
        case .merged: .purple
        case .closed: .red
        }
    }

    private func recommendationColor(_ rec: Recommendation) -> Color {
        switch rec {
        case .strongYes: .green
        case .yes: .green
        case .no: .red
        case .definitelyNot: .red
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
