import SwiftUI
import SwiftData
import CaptainsLogKit

/// A search hit with its model, fetched on the main context.
struct SearchRow: Identifiable {
    let hit: SearchHit
    let result: SearchResult

    var id: UUID { hit.id }
}

enum SearchResult {
    case person(Person)
    case project(Project)
    case todo(Todo)
    case log(LogEntry)
    case meeting(Meeting)
    case interview(Interview)
    case pr(PullRequest)
    case feedback(Feedback)
}

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Navigator.self) private var navigator
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var rows: [SearchRow] = []
    /// The query `rows` answer. Differs from the field's text while a search is pending.
    @State private var searchedQuery = ""
    @State private var kindFilter: SearchKind?
    @State private var selectedID: UUID?
    @State private var expandedID: UUID?
    @State private var pendingDelete: DeletableRecord?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var focusedField: LogFocusField?
    @FocusState private var prFocusedField: PRFocusField?

    private var query: String { navigator.searchQuery }

    private var visibleRows: [SearchRow] {
        guard let kindFilter else { return rows }
        return rows.filter { $0.hit.kind == kindFilter }
    }

    var body: some View {
        @Bindable var navigator = navigator
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visibleRows) { row in
                    resultRow(row)
                }
            }
            .contentColumn()
            .padding(.vertical, 8)
            .animation(.snappy(duration: 0.18), value: expandedID)
        }
        .overlay { emptyState }
        .contentShape(Rectangle())
        .onTapGesture { collapse() }
        .focusable()
        .focusEffectDisabled()
        .focused($focusedField, equals: .list)
        .onKeyPress(.return, phases: .down) { handleReturn($0) }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in moveSelection(by: 1); return .handled }
        .navigationTitle("Search")
        .searchable(text: $navigator.searchQuery, placement: .toolbar, prompt: "Search everything")
        .searchFocused($isSearchFocused)
        .onSubmit(of: .search) {
            selectedID = visibleRows.first?.id
            focusedField = .list
        }
        .onAppear { isSearchFocused = true }
        .task(id: query) { await search(query) }
        .toolbar { toolbarContent }
        .deleteConfirmation($pendingDelete) { record in
            rows.removeAll { $0.id == record.id }
            expandedID = nil
            focusedField = .list
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if SearchMatch.terms(of: query).isEmpty {
            ContentUnavailableView(
                "Search",
                systemImage: "magnifyingglass",
                description: Text("People, projects, todos, log entries, meetings, interviews, pull requests and feedback")
            )
        } else if searchedQuery == query && visibleRows.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Picker("Type", selection: $kindFilter) {
                Text("All (\(rows.count))").tag(SearchKind?.none)
                ForEach(SearchKind.allCases.filter { kind in rows.contains { $0.hit.kind == kind } }, id: \.self) { kind in
                    Text("\(kind.label) (\(rows.count { $0.hit.kind == kind }))").tag(SearchKind?.some(kind))
                }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func resultRow(_ row: SearchRow) -> some View {
        let isExpanded = expandedID == row.id
        switch row.result {
        case .log(let entry) where isExpanded:
            LogEntryCardView(
                entry: entry,
                projects: projects,
                focusedField: $focusedField,
                onCollapse: { collapse() }
            )
            .padding(.vertical, 2)
            .contextMenu { deleteMenu(row) }
        case .pr(let pr) where isExpanded:
            PRCardView(pr: pr, focusedField: $prFocusedField, onCollapse: { collapse() })
                .overlay(alignment: .topTrailing) {
                    GitHubButton(pr: pr, size: 14).padding(12)
                }
                .padding(.vertical, 2)
                .contextMenu { PRContextMenu(pr: pr) }
        default:
            SearchResultRow(row: row, terms: SearchMatch.terms(of: searchedQuery), isSelected: selectedID == row.id)
                .onTapGesture { tap(row) }
                .contextMenu { deleteMenu(row) }
        }
    }

    /// Only log entries, which open in place here; everything else is deleted where it opens.
    @ViewBuilder
    private func deleteMenu(_ row: SearchRow) -> some View {
        if case .log(let entry) = row.result {
            Button("Delete Entry…", systemImage: "trash", role: .destructive) { pendingDelete = .log(entry) }
        }
    }

    /// Log entries and PRs expand in place, like their own tabs: a click selects, a click on the
    /// selected row expands. Everything else opens on the first click, like links in the Log feed.
    private func tap(_ row: SearchRow) {
        if row.isExpandable && selectedID != row.id {
            collapse()
            selectedID = row.id
        } else {
            open(row)
        }
    }

    private func open(_ row: SearchRow) {
        selectedID = row.id
        switch row.result {
        case .log(let entry):
            expandedID = row.id
            focusedField = .title(entry.id)
        case .pr(let pr):
            expandedID = row.id
            prFocusedField = .notes(pr.id)
        case .person(let person): navigator.openPerson(person)
        case .feedback(let feedback): navigator.openPerson(feedback.person)
        case .meeting(let meeting): navigator.openMeeting(meeting)
        case .interview(let interview): navigator.openInterview(interview)
        case .todo(let todo): navigator.openTodo(todo)
        case .project(let project): navigator.openProject(project)
        }
    }

    private func collapse() {
        expandedID = nil
        prFocusedField = nil
        focusedField = .list
    }

    // MARK: - Keys

    private func moveSelection(by delta: Int) {
        let ids = visibleRows.map(\.id)
        guard !ids.isEmpty else { return }
        if let selectedID, let index = ids.firstIndex(of: selectedID) {
            self.selectedID = ids[max(0, min(ids.count - 1, index + delta))]
        } else {
            selectedID = delta > 0 ? ids.first : ids.last
        }
    }

    private func handleReturn(_ keyPress: KeyPress) -> KeyPress.Result {
        if keyPress.modifiers.contains(.shift) { return .ignored }
        if expandedID != nil {
            collapse()
            return .handled
        }
        guard let row = visibleRows.first(where: { $0.id == selectedID }) else { return .ignored }
        open(row)
        return .handled
    }

    private func handleEscape() -> KeyPress.Result {
        if expandedID != nil {
            collapse()
        } else {
            isSearchFocused = true
        }
        return .handled
    }

    // MARK: - Search

    /// Debounced; the text search runs on `Searcher`'s actor, then the hits are fetched here by id.
    private func search(_ query: String) async {
        guard !SearchMatch.terms(of: query).isEmpty else {
            rows = []
            searchedQuery = query
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        let hits = (try? await Searcher(modelContainer: modelContext.container).search(query)) ?? []
        guard !Task.isCancelled else { return }
        rows = resolve(hits)
        searchedQuery = query
        expandedID = nil
        selectedID = nil
        if let kindFilter, !rows.contains(where: { $0.hit.kind == kindFilter }) {
            self.kindFilter = nil
        }
    }

    /// Fetches each kind's models in one query. Hits whose record has since been deleted drop out.
    private func resolve(_ hits: [SearchHit]) -> [SearchRow] {
        let ids = Dictionary(grouping: hits, by: \.kind).mapValues { $0.map(\.id) }
        var results: [UUID: SearchResult] = [:]
        func load<M: PersistentModel>(_ kind: SearchKind, _ descriptor: ([UUID]) -> FetchDescriptor<M>, _ wrap: (M) -> (UUID, SearchResult)) {
            guard let kindIDs = ids[kind] else { return }
            for model in (try? modelContext.fetch(descriptor(kindIDs))) ?? [] {
                let (id, result) = wrap(model)
                results[id] = result
            }
        }
        load(.person, { ids in FetchDescriptor<Person>(predicate: #Predicate { ids.contains($0.id) }) }) { ($0.id, .person($0)) }
        load(.project, { ids in FetchDescriptor<Project>(predicate: #Predicate { ids.contains($0.id) }) }) { ($0.id, .project($0)) }
        load(.todo, { ids in FetchDescriptor<Todo>(predicate: #Predicate { ids.contains($0.id) }) }) { ($0.id, .todo($0)) }
        load(.log, { ids in FetchDescriptor<LogEntry>(predicate: #Predicate { ids.contains($0.id) }) }) { ($0.id, .log($0)) }
        load(.meeting, { ids in FetchDescriptor<Meeting>(predicate: #Predicate { ids.contains($0.id) }) }) { ($0.id, .meeting($0)) }
        load(.interview, { ids in FetchDescriptor<Interview>(predicate: #Predicate { ids.contains($0.id) }) }) { ($0.id, .interview($0)) }
        load(.pr, { ids in FetchDescriptor<PullRequest>(predicate: #Predicate { ids.contains($0.id) }) }) { ($0.id, .pr($0)) }
        load(.feedback, { ids in FetchDescriptor<Feedback>(predicate: #Predicate { ids.contains($0.id) }) }) { ($0.id, .feedback($0)) }
        return hits.compactMap { hit in results[hit.id].map { SearchRow(hit: hit, result: $0) } }
    }
}

extension SearchRow {
    var isExpandable: Bool {
        switch result {
        case .log, .pr: true
        default: false
        }
    }
}

// MARK: - Row

struct SearchResultRow: View {
    let row: SearchRow
    let terms: [String]
    let isSelected: Bool

    /// Fields that are the row's title, or shown in its context line, so a match there needs no snippet.
    private static let titleFields: Set<String> = ["title", "name", "candidateName", "person", "repo", "number", "author"]

    private var kind: SearchKind { row.hit.kind }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.icon)
                .font(.system(size: 12))
                .foregroundStyle(kind.color)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(highlighted(title))
                        .font(.headline)
                        .lineLimit(1)
                    if case .pr(let pr) = row.result {
                        GitHubButton(pr: pr)
                            .foregroundStyle(.secondary)
                    }
                }
                detail
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if let date = row.hit.date {
                    Text(DateLabel.day(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if case .pr(let pr) = row.result {
                    PRStatusBadge(status: pr.displayStatus)
                        .scaleEffect(0.85, anchor: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    /// From the model, so edits made in an expanded card show without searching again.
    private var title: String {
        switch row.result {
        case .person(let p): p.name
        case .project(let p): p.name
        case .todo(let t): t.title
        case .log(let e): e.title
        case .meeting(let m): m.title
        case .interview(let i): i.candidateName
        case .pr(let pr): pr.title
        case .feedback: row.hit.title
        }
    }

    /// The text around the match, or when the title matched, a line of context instead.
    @ViewBuilder
    private var detail: some View {
        let match = row.hit.match
        if !Self.titleFields.contains(match.field) {
            Text(snippetText(match))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else if let context, !context.isEmpty {
            Text(highlighted(context))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var context: String? {
        let text: String? = switch row.result {
        case .person(let p): [p.email, p.slackHandle.map { "@\($0)" }].compactMap { $0 }.joined(separator: "  ")
        case .project(let p): p.notes
        case .todo(let t): t.project?.name ?? t.notes
        case .log(let e): e.content
        case .meeting(let m): m.summary ?? m.notes
        case .interview(let i): i.role
        case .pr(let pr): ["\(pr.repo) #\(pr.number)", pr.isAuthoredByMe ? nil : pr.author?.name].compactMap { $0 }.joined(separator: "  ")
        case .feedback(let f): f.content
        }
        return text.map { $0.replacing(/\s+/, with: " ") }
    }

    /// The record's own text needs no label; other fields say where the match was.
    private func snippetText(_ match: SearchMatch) -> AttributedString {
        let snippet = highlighted(match.snippet)
        guard match.field != "content" else { return snippet }
        var label = AttributedString(Self.label(for: match.field) + ": ")
        label.foregroundColor = .secondary.opacity(0.7)
        return label + snippet
    }

    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        for range in SearchMatch.wordStarts(of: terms, in: text) {
            result += AttributedString(text[cursor..<range.lowerBound])
            var match = AttributedString(text[range])
            match.inlinePresentationIntent = .stronglyEmphasized
            match.foregroundColor = .primary
            result += match
            cursor = range.upperBound
        }
        result += AttributedString(text[cursor...])
        return result
    }

    /// "prepNotes" -> "Prep notes".
    private static func label(for field: String) -> String {
        let words = field.replacing(/([a-z])([A-Z])/) { "\($0.1) \($0.2.lowercased())" }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

extension SearchKind {
    var label: String {
        switch self {
        case .person: "People"
        case .project: "Projects"
        case .todo: "Todos"
        case .log: "Log"
        case .meeting: "Meetings"
        case .interview: "Interviews"
        case .pr: "Pull Requests"
        case .feedback: "Feedback"
        }
    }

    var icon: String {
        switch self {
        case .person: SidebarItem.people.icon
        case .project: "folder"
        case .todo: FeedItemType.todo.icon
        case .log: FeedItemType.log.icon
        case .meeting: FeedItemType.meeting.icon
        case .interview: FeedItemType.interview.icon
        case .pr: FeedItemType.pullRequest.icon
        case .feedback: "text.bubble"
        }
    }

    var color: Color {
        switch self {
        case .person: .indigo
        case .project: .cyan
        case .todo: FeedItemType.todo.color
        case .log: FeedItemType.log.color
        case .meeting: FeedItemType.meeting.color
        case .interview: FeedItemType.interview.color
        case .pr: FeedItemType.pullRequest.color
        case .feedback: .pink
        }
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
    .previewEnvironment()
}
