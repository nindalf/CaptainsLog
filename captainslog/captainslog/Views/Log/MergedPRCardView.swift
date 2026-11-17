import SwiftUI
import SwiftData
import CaptainsLogKit

/// A merged PR opened in the Log, laid out like a log entry's card. The title is GitHub's; the notes
/// and project are mine.
struct MergedPRCardView: View {
    @Bindable var pr: PullRequest
    let projects: [Project]
    var focusedField: FocusState<LogFocusField?>.Binding
    var onCollapse: () -> Void

    private var notesBinding: Binding<String> {
        Binding(
            get: { pr.notes ?? "" },
            set: { pr.notes = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pr.title)
                .textSelection(.enabled)

            MarkdownEditor(
                text: notesBinding,
                placeholder: "Notes",
                minHeight: 40,
                maxHeight: 200,
                showSlackControls: false,
                focus: focusedField,
                focusValue: .content(pr.id),
                onReturn: onCollapse
            )

            HStack(spacing: 8) {
                Group {
                    if let merged = pr.mergedAt {
                        Text("Merged \(merged, format: .dateTime.day().month(.abbreviated).hour().minute())")
                    }
                    CopyablePRNumber(pr: pr)
                    if let additions = pr.additions, let deletions = pr.deletions {
                        ChangeStats(additions: additions, deletions: deletions)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                GitHubButton(pr: pr, size: 14)
                ProjectControl(current: pr.project, projects: projects) { pr.project = $0 }
            }
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { }
        .onDisappear { try? pr.modelContext?.save() }
    }
}
