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
    @Environment(Navigator.self) private var navigator

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

    private var expandedTimestamp: Date? {
        logEntries.first { $0.id == expandedID }?.timestamp
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
        ScrollViewReader { proxy in
            ScrollView {
                feedListContent
            }
            // An open entry given another day moves to that day's group; follow it there.
            .onChange(of: expandedTimestamp) { _, timestamp in
                guard timestamp != nil, let expandedID else { return }
                withAnimation(.snappy(duration: 0.18)) { proxy.scrollTo(expandedID) }
            }
            .onAppear { revealRequestedEntry(proxy) }
            .onChange(of: navigator.revealRecordID) { revealRequestedEntry(proxy) }
        }
        .contentShape(Rectangle())
        .onTapGesture { collapseAndCommit() }
        .focusable()
        .focusEffectDisabled()
        .focused($focusedField, equals: .list)
        .onAppear { if focusesOnAppear { DispatchQueue.main.async { focusedField = .list } } }
        .onKeyPress(.return, phases: .down) { handleReturnKey($0) }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in handleArrow(delta: -1) }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in handleArrow(delta: 1) }
        // The Delete key arrives as U+007F, which `.delete` doesn't match.
        .onKeyPress(phases: .down) { press in
            press.characters == "\u{7F}" || press.key == .deleteForward ? handleDelete() : .ignored
        }
        .selectionCommands(selectionCommands, claimsOnAppear: focusesOnAppear, selection: [selectedID, expandedID]) {
            focusedField = .list
        }
    }

    /// Delete on the selected item, as the Delete key does, open or not; a PR opens in GitHub instead.
    private var selectionCommands: CommandHandlers {
        var handlers = CommandHandlers()
        guard draft == nil, let selectedID, let item = feedItem(for: selectedID) else { return handlers }
        if case .pullRequest(let pr) = item {
            handlers[.openInGitHub] = { NSWorkspace.shared.open(pr.url) }
        } else {
            handlers[.delete] = {
                guard let id = self.selectedID, let item = feedItem(for: id) else { return }
                _ = requestDelete(item)
            }
        }
        return handlers
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
                    systemImage: RecordKind.log.icon,
                    description: Text(AppCommand.newLogEntry.help("Add a log entry"))
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
        SectionHeader(title: label).pinnedSectionHeader()
    }

    // MARK: - Row builder

    @ViewBuilder
    private func feedRow(for item: FeedItem) -> some View {
        switch item {
        case .log(let entry):
            logEntryRow(entry)
        case .meeting, .interview:
            FeedRowView(item: item, isSelected: selectedID == item.id)
                .onRecordClick(select: { select(item.id) }, open: { openPage(item) })
                .contextMenu { deleteMenu(item) }
        case .pullRequest(let pr):
            pullRequestRow(pr)
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
                .onRecordClick(select: { select(entry.id) }, open: { expand(entry.id) })
                .contextMenu { deleteMenu(.log(entry)) }
        }
    }

    @ViewBuilder
    private func pullRequestRow(_ pr: PullRequest) -> some View {
        if expandedID == pr.id {
            MergedPRCardView(
                pr: pr,
                projects: projects,
                focusedField: $focusedField,
                onCollapse: { collapseAndCommit() }
            )
            .padding(.vertical, 2)
            .contextMenu { PRContextMenu(pr: pr) }
        } else {
            FeedRowView(item: .pullRequest(pr), isSelected: selectedID == pr.id)
                .onRecordClick(select: { select(pr.id) }, open: { expand(pr.id) })
                .contextMenu { PRContextMenu(pr: pr) }
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
            .onRecordClick(select: { select(todo.id) }, open: { expand(todo.id) })
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

    /// Opens a log entry's, completed todo's or PR's card, in its title or, for a PR, whose title
    /// is GitHub's, its notes.
    /// A log entry opened from elsewhere: shown whatever the filter, expanded and scrolled to.
    private func revealRequestedEntry(_ proxy: ScrollViewProxy) {
        guard let id = navigator.revealRecordID, logEntries.contains(where: { $0.id == id }) else { return }
        navigator.revealRecordID = nil
        if typeFilter != nil && typeFilter != .log { typeFilter = nil }
        expand(id)
        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
    }

    private func expand(_ id: UUID) {
        commitDraft()
        selectedID = id
        withAnimation(.snappy(duration: 0.15)) {
            expandedID = id
        }
        if case .pullRequest = feedItem(for: id) {
            focusedField = .content(id)
        } else {
            focusedField = .title(id)
        }
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
        case .log, .todo, .pullRequest:
            expand(selectedID)
        case .meeting, .interview:
            openPage(item)
        }
        return .handled
    }

    private func select(_ id: UUID) {
        if selectedID != id { collapseAndCommit() }
        selectedID = id
    }

    /// Meetings and interviews have notes, so they open as a page.
    private func openPage(_ item: FeedItem) {
        selectedID = item.id
        switch item {
        case .meeting(let meeting): navigator.openMeeting(meeting)
        case .interview(let interview): navigator.openInterview(interview)
        default: break
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
