import SwiftUI
import CaptainsLogKit

/// A log entry's controls, at the bottom right of its card: source, tags, project, day, privacy.
/// Set tags, a project or a day other than today show as pills, else as icons.
struct LogEntryControls: View {
    @Bindable var entry: LogEntry
    let projects: [Project]
    /// Quick Entry keeps its project here until Save, since relating a draft inserts it.
    var pendingProject: Binding<UUID?>? = nil

    @State private var showTags = false
    @State private var showDate = false

    private var project: Project? {
        guard let pendingProject else { return entry.project }
        return projects.first { $0.id == pendingProject.wrappedValue }
    }

    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            // Manual is the default; only the other sources say anything.
            if entry.source != .manual {
                Text(entry.source.rawValue).cardPill(.secondary)
            }
            tagsControl
            projectControl
            dateControl
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

    private var dateControl: some View {
        Button { showDate.toggle() } label: {
            if Calendar.current.isDateInToday(entry.timestamp) {
                Image(systemName: "calendar")
            } else {
                Text(DateLabel.day(entry.timestamp)).cardPill(.blue)
            }
        }
        .buttonStyle(.plain)
        .help("Date")
        .popover(isPresented: $showDate) { LogDatePopover(entry: entry) }
    }

    private var projectControl: some View {
        ProjectControl(current: project, projects: projects) { picked in
            if let pendingProject {
                pendingProject.wrappedValue = picked?.id
            } else {
                entry.project = picked
            }
        }
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
