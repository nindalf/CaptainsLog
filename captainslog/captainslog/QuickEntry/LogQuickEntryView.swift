import SwiftUI
import SwiftData
import CaptainsLogKit

/// Quick Entry for a log entry: title, content, and a log card's controls (tags, project, privacy).
struct LogQuickEntryView: View {
    var onClose: () -> Void
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Project> { $0.completedDate == nil }, sort: \Project.sortOrder) private var projects: [Project]

    /// Uninserted until Save, and never related to a project before then (that would insert it),
    /// so Cancel leaves nothing behind. The project waits in `projectID`.
    @State private var draft = LogEntry(timestamp: .now, source: .manual, title: "", content: "")
    @State private var projectID: UUID?
    @FocusState private var focus: LogFocusField?

    private var project: Project? { projects.first { $0.id == projectID } }

    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        QuickEntryCard(canSave: canSave, onSave: save, onClose: onClose, onHeightChange: onHeightChange) {
            entry
        }
        .task { focus = .title(draft.id) }
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: FeedItemType.log.icon)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.secondary.opacity(0.6))
                TextField("New Log Entry", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focusedWithTagCompletion($focus, equals: .title(draft.id))
                    .onSubmit(save)
            }
            MarkdownEditor(
                text: $draft.content,
                placeholder: "Content",
                minHeight: 44,
                maxHeight: 220,
                showSlackControls: false,
                focus: $focus,
                focusValue: .content(draft.id)
            )
            .padding(.leading, 30)
            LogEntryControls(entry: draft, projects: projects, pendingProject: $projectID)
                .padding(.leading, 30)
        }
    }

    private func save() {
        let title = draft.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        draft.title = title
        // Now, on the day picked for it.
        let day = draft.timestamp
        draft.timestamp = .now
        draft.move(toDay: day)
        modelContext.insert(draft)
        draft.project = project
        _ = try? draft.linkMentionedPeople(in: modelContext)
        try? modelContext.save()
        onClose()
    }
}

#Preview {
    LogQuickEntryView(onClose: {})
        .modelContainer(PreviewData.container)
}
