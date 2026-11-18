import SwiftUI
import SwiftData
import CaptainsLogKit

struct PersonDetailView: View {
    @Bindable var person: Person
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(Navigator.self) private var navigator
    @State private var showMergeSheet = false
    @State private var expandedFeedbackID: UUID?
    /// The row last clicked in any of the page's lists.
    @State private var selectedRowID: UUID?
    @State private var expandedPRID: UUID?
    @FocusState private var prFocus: PRFocusField?

    // Queried rather than read from `person.feedback`: an insert only sets the inverse side,
    // which does not notify observers of `person`, so the section would not redraw.
    @Query private var sortedFeedback: [Feedback]
    // Likewise `person.logEntries`: a card links people from the entry's side.
    @Query private var logEntries: [LogEntry]

    init(person: Person) {
        _person = Bindable(person)
        let personID = person.id
        _sortedFeedback = Query(
            filter: #Predicate<Feedback> { $0.person.id == personID },
            sort: \Feedback.date,
            order: .reverse
        )
        _logEntries = Query(
            filter: #Predicate<LogEntry> { entry in entry.people.contains { $0.id == personID } },
            sort: \LogEntry.timestamp,
            order: .reverse
        )
    }

    /// Feedback, PRs and meetings show the most recent this many, the rest behind Show More.
    private static let rowLimit = 10

    private var authoredPRs: [PullRequest] {
        (person.authoredPRs ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    private var reviewedPRs: [PullRequest] {
        (person.reviewedPRs ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    private var meetings: [Meeting] {
        (person.meetings ?? []).sorted { $0.date > $1.date }
    }

    private var interviews: [Interview] {
        (person.interviews ?? []).sorted { $0.date > $1.date }
    }

    var body: some View {
        DetailPage {
            DetailHeader(title: $person.name, placeholder: "Name", onCommit: person.trimWhitespace) {
                if !(person.githubHandle ?? "").isEmpty {
                    Toggle(isOn: syncsPullRequests) {
                        Text("Sync all their PRs")
                    }
                    .toggleStyle(.checkbox)
                    .help("Open and merged PRs in your repos, not just review requests.")
                }
            }

            DetailProperties {
                DetailTextProperty(label: "Email", prompt: "Add email", text: optionalBinding(\.email), onCommit: person.trimWhitespace)
                DetailTextProperty(label: "GitHub", prompt: "Add GitHub handle", text: optionalBinding(\.githubHandle), onCommit: person.trimWhitespace)
                DetailTextProperty(label: "Slack", prompt: "Add Slack handle", text: optionalBinding(\.slackHandle), onCommit: person.trimWhitespace)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.top, -12)

            LinkedTodoList(person: person)

            feedbackSection

            if !authoredPRs.isEmpty {
                DetailSection("Authored PRs", count: authoredPRs.count) {
                    DetailRows(data: authoredPRs, limit: Self.rowLimit) { pr in prRow(pr) }
                }
            }
            if !reviewedPRs.isEmpty {
                DetailSection("Reviewed PRs", count: reviewedPRs.count) {
                    DetailRows(data: reviewedPRs, limit: Self.rowLimit) { pr in prRow(pr) }
                }
            }
            if !meetings.isEmpty {
                DetailSection("Meetings", count: meetings.count) {
                    DetailRows(data: meetings, limit: Self.rowLimit) { meeting in
                        MeetingRecordRow(meeting: meeting, date: .day(meeting.date), isSelected: selectedRowID == meeting.id, isPadded: false)
                            .onRecordClick(isSelected: selectedRowID == meeting.id, select: { select(meeting.id) }, open: { navigator.openMeeting(meeting) })
                    }
                }
            }
            if !interviews.isEmpty {
                DetailSection("Interviews", count: interviews.count) {
                    DetailRows(data: interviews) { interview in
                        InterviewRecordRow(interview: interview, date: .day(interview.date), isSelected: selectedRowID == interview.id, isPadded: false)
                            .onRecordClick(isSelected: selectedRowID == interview.id, select: { select(interview.id) }, open: { navigator.openInterview(interview) })
                    }
                }
            }
            if !logEntries.isEmpty {
                DetailSection("Log Entries", count: logEntries.count) {
                    DetailRows(data: logEntries) { entry in
                        // Opens on the Log, where its card lives.
                        LogRecordRow(entry: entry, date: .day(entry.timestamp), isSelected: selectedRowID == entry.id, isPadded: false)
                            .onRecordClick(isSelected: selectedRowID == entry.id, select: { select(entry.id) }, open: { navigator.openLogEntry(entry) })
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showMergeSheet = true
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
                .help("Merge a duplicate person into this one")
            }
        }
        // A field still focused when the page goes doesn't lose focus first.
        .onDisappear {
            if !person.isDeleted { person.trimWhitespace() }
        }
        .pageCommands(pageCommands)
        .sheet(isPresented: $showMergeSheet) {
            PersonMergePicker(keep: person) { other in
                person.absorb(other, in: modelContext)
                showMergeSheet = false
            }
        }
    }

    private var pageCommands: CommandHandlers {
        var handlers = CommandHandlers()
        handlers[.addFeedback] = { addFeedback() }
        handlers[.mergePerson] = { showMergeSheet = true }
        return handlers
    }

    // MARK: - Feedback

    private var feedbackSection: some View {
        DetailSection("Feedback", count: sortedFeedback.isEmpty ? nil : sortedFeedback.count, onAdd: addFeedback, addHelp: "Add Feedback") {
            if sortedFeedback.isEmpty {
                Button("Add Feedback", systemImage: "plus", action: addFeedback)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            DetailRows(data: sortedFeedback, limit: Self.rowLimit) { item in
                if expandedFeedbackID == item.id {
                    FeedbackEditor(
                        feedback: item,
                        onCollapse: { expandedFeedbackID = nil },
                        onDelete: { delete(item) }
                    )
                } else {
                    FeedbackSummaryRow(feedback: item)
                        .selectionHighlight(selectedRowID == item.id)
                        .onRecordClick(isSelected: selectedRowID == item.id, select: { select(item.id) }, open: { expandedFeedbackID = item.id })
                }
            }
        }
        .animation(.snappy(duration: 0.18), value: expandedFeedbackID)
        // An item left blank when it closes was never written, so it goes.
        .onChange(of: expandedFeedbackID) { closed, _ in deleteIfBlank(closed) }
        .onDisappear { deleteIfBlank(expandedFeedbackID) }
    }

    /// Selecting any row on the page closes an open PR card.
    private func select(_ id: UUID) {
        selectedRowID = id
        if expandedPRID != id { expandedPRID = nil }
    }

    /// Expands in place, as on the PR tab.
    @ViewBuilder
    private func prRow(_ pr: PullRequest) -> some View {
        if expandedPRID == pr.id {
            PRCardView(pr: pr, focusedField: $prFocus, date: .day(pr.createdAt), onCollapse: { expandedPRID = nil })
                .contextMenu { PRContextMenu(pr: pr) }
        } else {
            PRRecordRow(pr: pr, date: .day(pr.createdAt), isSelected: selectedRowID == pr.id, isPadded: false)
                .onRecordClick(isSelected: selectedRowID == pr.id, select: { select(pr.id) }, open: {
                    selectedRowID = pr.id
                    expandedPRID = pr.id
                    prFocus = .notes(pr.id)
                })
                .contextMenu { PRContextMenu(pr: pr) }
        }
    }

    private func addFeedback() {
        let item = Feedback(date: .now, person: person, content: "")
        modelContext.insert(item)
        // Open straight away so the new item can be typed into.
        expandedFeedbackID = item.id
    }

    private func delete(_ feedback: Feedback) {
        if expandedFeedbackID == feedback.id { expandedFeedbackID = nil }
        modelContext.delete(feedback)
    }

    private func deleteIfBlank(_ id: UUID?) {
        guard let item = sortedFeedback.first(where: { $0.id == id }), !item.isDeleted,
              item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        modelContext.delete(item)
    }

    // MARK: - Helpers

    private var syncsPullRequests: Binding<Bool> {
        Binding(
            get: { person.syncsPullRequests },
            set: { newValue in
                person.syncsPullRequests = newValue
                if newValue {
                    try? modelContext.save()
                    syncCoordinator.syncGitHubNow()
                }
            }
        )
    }

    private func optionalBinding(_ keyPath: ReferenceWritableKeyPath<Person, String?>) -> Binding<String?> {
        Binding(
            get: { person[keyPath: keyPath] },
            set: { person[keyPath: keyPath] = $0 }
        )
    }
}

// MARK: - Feedback rows

/// One-line collapsed form of a feedback item: first line of content, date.
private struct FeedbackSummaryRow: View {
    let feedback: Feedback

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(preview)
                .lineLimit(1)
                .foregroundStyle(feedback.content.isEmpty ? .tertiary : .primary)
            Spacer()
            Text(DateLabel.day(feedback.date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }

    private var preview: String {
        let firstLine = feedback.content.split(whereSeparator: \.isNewline).first.map(String.init)
        return firstLine ?? "No content"
    }
}

private struct FeedbackEditor: View {
    @Bindable var feedback: Feedback
    var onCollapse: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: onCollapse) {
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.semibold))
                        .frame(width: 16)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Collapse")
                Spacer()
                DayField(date: $feedback.date)
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete Feedback")
            }
            MarkdownEditor(
                text: $feedback.content,
                placeholder: "Feedback for \(feedback.person.name)…",
                minHeight: 60
            )
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Merge picker

private struct PersonMergePicker: View {
    let keep: Person
    var onSelect: (Person) -> Void

    @Query(sort: \Person.name) private var allPeople: [Person]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var candidates: [Person] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return allPeople
            .filter { $0.id != keep.id }
            .filter { trimmed.isEmpty || $0.name.lowercased().contains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List(candidates) { person in
                Button {
                    onSelect(person)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                        if let handle = person.githubHandle ?? person.email {
                            Text(handle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Merge into \(keep.name)")
            .searchable(text: $searchText, prompt: "Search people")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}

// MARK: - PR row

#Preview {
    NavigationStack {
        PersonDetailView(person: PreviewData.makePerson())
    }
    .previewEnvironment()
}
