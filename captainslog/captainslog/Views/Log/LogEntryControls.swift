import SwiftUI
import CaptainsLogKit

/// A log entry's controls, at the bottom right of its card: source, tags, project, privacy.
/// Set tags or a project show as pills, else as icons.
struct LogEntryControls: View {
    @Bindable var entry: LogEntry
    let projects: [Project]

    @State private var showTags = false

    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            // Manual is the default; only the other sources say anything.
            if entry.source != .manual {
                Text(entry.source.rawValue).cardPill(.secondary)
            }
            tagsControl
            projectControl
            PrivacyEye(isOn: $entry.isPrivate)
        }
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
    }

    private var tagsControl: some View {
        Button { showTags.toggle() } label: {
            if entry.tags.isEmpty {
                Image(systemName: "tag")
            } else {
                HStack(spacing: 4) {
                    ForEach(entry.tags, id: \.self) { Text($0).cardPill(.gray) }
                }
            }
        }
        .buttonStyle(.plain)
        .help("Tags")
        .popover(isPresented: $showTags) { LogEntryTagPopover(entry: entry) }
    }

    private var projectControl: some View {
        ProjectControl(current: entry.project, projects: projects) { entry.project = $0 }
    }
}

struct LogEntryTagPopover: View {
    @Bindable var entry: LogEntry
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !entry.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(entry.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                            Button { entry.tags.removeAll { $0 == tag } } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }

            TextField("Add tag", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    let trimmed = newTag.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && !entry.tags.contains(trimmed) {
                        entry.tags.append(trimmed)
                    }
                    newTag = ""
                }
        }
        .padding(12)
        .frame(width: 200)
    }
}
