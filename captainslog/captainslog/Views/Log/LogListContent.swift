import SwiftUI
import SwiftData
import CaptainsLogKit

/// The log feed proper: rows, drafts, keyboard. Shared by the Log tab and the dashboard pane.
/// Controls that live in the tab's toolbar (type filter, add) are inputs so the host decides how to present them.
struct LogListContent: View {
    @Binding var typeFilter: FeedItemType?
    /// Incremented by the host to request a new draft.
    var addTick: Int = 0
    /// The Dashboard pane fills its card rather than sitting in the content column.
    var fillsWidth = false
    var focusesOnAppear: Bool = true
    /// Off on the Dashboard, whose Today list already shows them.
    var includesCompletedTodos = true

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \LogEntry.timestamp, order: .reverse)
    private var logEntries: [LogEntry]

    @Query(sort: \Meeting.date, order: .reverse)
    private var meetings: [Meeting]

    @Query(sort: \Interview.date, order: .reverse)
    private var interviews: [Interview]

    @Query(sort: \PullRequest.createdAt, order: .reverse)
    private var pullRequests: [PullRequest]

    @Query(filter: #Predicate<Todo> { $0.completedDate != nil && $0.trashedDate == nil },
           sort: \Todo.sortOrder)
    private var completedTodos: [Todo]

    @Query(sort: \Project.name) private var projects: [Project]

    @State private var selectedID: UUID?
    @State private var expandedID: UUID?
    @State private var draft: LogEntry?
    @State private var pendingDelete: DeletableRecord?
    @State private var pendingReopen: [Todo] = []
    @FocusState private var focusedField: LogFocusField?

    private var feedItems: [FeedItem] {
        var items: [FeedItem] = []
        if typeFilter == nil || typeFilter == .log {
            items += logEntries.map { .log($0) }
        }
        if typeFilter == nil || typeFilter == .meeting {
            items += meetings.filter(Feed.includes).map { .meeting($0) }
        }
        if typeFilter == nil || typeFilter == .interview {
            items += interviews.filter(Feed.includes).map { .interview($0) }
        }
        if typeFilter == nil || typeFilter == .pullRequest {
            items += pullRequests.filter(Feed.includes).map { .pullRequest($0) }
        }
        if includesCompletedTodos && (typeFilter == nil || typeFilter == .todo) {
            items += completedTodos.map { .todo($0) }
        }
        return items.sorted { $0.timestamp > $1.timestamp }
    }

    private var dateGroups: [FeedDateGroup] {
        FeedDateGroup.group(feedItems)
    }

    private var flatItemIDs: [UUID] {
        feedItems.map(\.id)
    }

    private func feedItem(for id: UUID) -> FeedItem? {
        feedItems.first { $0.id == id }
    }

    var body: some View {
        feedScrollView
            .onChange(of: addTick) { createDraft() }
            .reopenConfirmation($pendingReopen)
            .deleteConfirmation($pendingDelete) { record in
                if expandedID == record.id { expandedID = nil }
                selectedID = nextSelectionAfterDelete(record.id)
            }
    }

    // MARK: - View hierarchy

    private var feedScrollView: some View {
        ScrollView {
            feedListContent
        }
        .contentShape(Rectangle())
        .onTapGesture { collapseAndCommit() }
        .focusable()
        .focusEffectDisabled()
        .focused($focusedField, equals: .list)
        .onAppear { if focusesOnAppear { focusedField = .list } }
        .onKeyPress(.return, phases: .down) { handleReturnKey($0) }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in handleArrow(delta: -1) }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in handleArrow(delta: 1) }
        // The Delete key arrives as U+007F, which `.delete` doesn't match.
        .onKeyPress(phases: .down) { press in
            press.characters == "\u{7F}" || press.key == .deleteForward ? handleDelete() : .ignored
        }
    }

    private var feedListContent: some View {
        LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
            draftCard

            ForEach(dateGroups) { group in
                Section {
                    ForEach(group.items) { item in
                        feedRow(for: item)
                    }
                } header: {
                    dateHeader(group.label)
                }
            }

            if feedItems.isEmpty && draft == nil {
                ContentUnavailableView(
                    "No Entries",
                    systemImage: "book",
                    description: Text("Press Cmd+N to add a log entry")
                )
                .padding(.top, 40)
            }
        }
        .contentColumn(!fillsWidth)
        .animation(.snappy(duration: 0.18), value: expandedID)
    }

    @ViewBuilder
    private var draftCard: some View {
        if let draft {
            LogEntryCardView(
                entry: draft,
                projects: projects,
                focusedField: $focusedField,
                onCollapse: { collapseAndCommit() }
            )
            // Clear of the heading, as the date headers' top padding is.
            .padding(.top, 16)
            .padding(.bottom, 2)
        }
    }

    private func dateHeader(_ label: String) -> some View {
        Text(label)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .padding(.horizontal, 4)
            .background(.background)
    }

    // MARK: - Row builder

    @ViewBuilder
    private func feedRow(for item: FeedItem) -> some View {
        switch item {
        case .log(let entry):
            logEntryRow(entry)
        case .meeting(let meeting):
            NavigationLink(value: meeting) {
                FeedRowView(item: item, isSelected: selectedID == item.id)
            }
            .buttonStyle(.plain)
            .contextMenu { deleteMenu(item) }
        case .interview(let interview):
            NavigationLink(value: interview) {
                FeedRowView(item: item, isSelected: selectedID == item.id)
            }
            .buttonStyle(.plain)
            .contextMenu { deleteMenu(item) }
        case .pullRequest(let pr):
            FeedRowView(item: item, isSelected: selectedID == item.id)
                .onTapGesture {
                    NSWorkspace.shared.open(pr.url)
                }
        case .todo(let todo):
            todoRow(todo)
        }
    }

    /// PRs mirror GitHub, so they have none.
    @ViewBuilder
    private func deleteMenu(_ item: FeedItem) -> some View {
        switch item {
        case .log: Button("Delete Entry…", systemImage: "trash", role: .destructive) { requestDelete(item) }
        case .meeting: Button("Delete Meeting…", systemImage: "trash", role: .destructive) { requestDelete(item) }
        case .interview: Button("Delete Interview…", systemImage: "trash", role: .destructive) { requestDelete(item) }
        case .todo: Button("Move to Trash", systemImage: "trash") { requestDelete(item) }
        case .pullRequest: EmptyView()
        }
    }

    @ViewBuilder
    private func logEntryRow(_ entry: LogEntry) -> some View {
        if expandedID == entry.id {
            LogEntryCardView(
                entry: entry,
                projects: projects,
                focusedField: $focusedField,
                onCollapse: { collapseAndCommit() }
            )
            .padding(.vertical, 2)
            .contextMenu { deleteMenu(.log(entry)) }
        } else {
            FeedRowView(item: .log(entry), isSelected: selectedID == entry.id)
                .onTapGesture {
                    if selectedID == entry.id {
                        expand(entry.id)
                    } else {
                        collapseAndCommit()
                        selectedID = entry.id
                    }
                }
                .contextMenu { deleteMenu(.log(entry)) }
        }
    }

    @ViewBuilder
    private func todoRow(_ todo: Todo) -> some View {
        if expandedID == todo.id {
            CompletedTodoCardView(
                todo: todo,
                projects: projects,
                focusedField: $focusedField,
                onCollapse: { collapseAndCommit() }
            )
            .padding(.vertical, 2)
            .contextMenu { deleteMenu(.todo(todo)) }
        } else {
            FeedRowView(item: .todo(todo), isSelected: selectedID == todo.id, onReopen: {
                ReopenConfirmation.request([todo], pending: &pendingReopen, in: modelContext)
            })
            .onTapGesture {
                if selectedID == todo.id {
                    expand(todo.id)
                } else {
                    collapseAndCommit()
                    selectedID = todo.id
                }
            }
            .contextMenu { deleteMenu(.todo(todo)) }
        }
    }

    // MARK: - Draft management

    private func createDraft() {
        commitDraft()
        let newDraft = LogEntry(
            timestamp: .now,
            source: .manual,
            title: "",
            content: ""
        )
        draft = newDraft
        expandedID = nil
        focusedField = .title(newDraft.id)
    }

    private func commitDraft() {
        guard let draft else { return }
        let title = draft.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            modelContext.insert(draft)
            try? modelContext.save()
        }
        self.draft = nil
    }

    private func collapseAndCommit() {
        withAnimation(.snappy(duration: 0.15)) {
            expandedID = nil
        }
        commitDraft()
        focusedField = .list
    }

    // MARK: - Entry actions

    /// Log entries, meetings and interviews delete for good after a confirmation; todos go to the
    /// Trash at once, as they do in Todos. Returns false for PRs, which don't delete.
    @discardableResult
    private func requestDelete(_ item: FeedItem) -> Bool {
        switch item {
        case .log(let entry): pendingDelete = .log(entry)
        case .meeting(let meeting): pendingDelete = .meeting(meeting)
        case .interview(let interview): pendingDelete = .interview(interview)
        case .todo(let todo):
            if expandedID == todo.id { expandedID = nil; focusedField = .list }
            selectedID = nextSelectionAfterDelete(todo.id)
            todo.moveToTrash()
            try? modelContext.save()
        case .pullRequest: return false
        }
        return true
    }

    private func nextSelectionAfterDelete(_ id: UUID) -> UUID? {
        let ids = flatItemIDs
        guard let index = ids.firstIndex(of: id) else { return nil }
        if index + 1 < ids.count { return ids[index + 1] }
        if index > 0 { return ids[index - 1] }
        return nil
    }

    /// Opens a log entry's or completed todo's card.
    private func expand(_ id: UUID) {
        commitDraft()
        selectedID = id
        withAnimation(.snappy(duration: 0.15)) {
            expandedID = id
        }
        focusedField = .title(id)
    }

    // MARK: - Selection

    private func moveSelection(by delta: Int) {
        let ids = flatItemIDs
        guard !ids.isEmpty else { return }
        if let selectedID, let index = ids.firstIndex(of: selectedID) {
            let newIndex = max(0, min(ids.count - 1, index + delta))
            self.selectedID = ids[newIndex]
        } else {
            selectedID = delta > 0 ? ids.first : ids.last
        }
    }

    // MARK: - Key handlers

    private func handleArrow(delta: Int) -> KeyPress.Result {
        // While a card is open, arrows belong to its text fields.
        guard expandedID == nil, draft == nil else { return .ignored }
        moveSelection(by: delta)
        return .handled
    }

    private func handleReturnKey(_ keyPress: KeyPress) -> KeyPress.Result {
        if keyPress.modifiers.contains(.shift) { return .ignored }
        if expandedID != nil {
            collapseAndCommit()
            return .handled
        }
        guard let selectedID, let item = feedItem(for: selectedID) else { return .ignored }
        switch item {
        case .log, .todo:
            expand(selectedID)
            return .handled
        default:
            return .ignored
        }
    }

    private func handleEscape() -> KeyPress.Result {
        if let draft {
            let title = draft.title.trimmingCharacters(in: .whitespaces)
            if title.isEmpty {
                self.draft = nil
            } else {
                collapseAndCommit()
            }
            focusedField = .list
            return .handled
        }
        if expandedID != nil {
            collapseAndCommit()
            return .handled
        }
        return .ignored
    }

    private func handleDelete() -> KeyPress.Result {
        // While a card is open, Delete belongs to its text fields.
        guard expandedID == nil, draft == nil, let selectedID, let item = feedItem(for: selectedID) else { return .ignored }
        return requestDelete(item) ? .handled : .ignored
    }
}
