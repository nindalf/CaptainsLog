import SwiftUI
import SwiftData
import CaptainsLogKit

/// The command palette, and the same box searching records, choosing a project or choosing one of
/// today's meetings to join. Floats over the window. Return runs the selected row; Escape
/// or a click outside closes it.
struct CommandPalette: View {
    let request: PaletteRequest
    /// Closes the palette, then runs `action` once focus is back where it was.
    var onClose: (_ action: (() -> Void)?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(Navigator.self) private var navigator
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<Project> { $0.completedDate == nil }, sort: \Project.sortOrder) private var projects: [Project]

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var searchRows: [SearchRow] = []
    @State private var meetings: [CalendarEvent] = []
    @FocusState private var isFieldFocused: Bool

    private static let searchLimit = 50

    private enum Row: Identifiable {
        case command(AppCommand)
        case record(SearchRow)
        case project(Project?)
        case meeting(CalendarEvent)

        var id: String {
            switch self {
            case .command(let command): command.id
            case .record(let row): row.id.uuidString
            case .project(let project): project?.id.uuidString ?? "none"
            case .meeting(let event): event.id.uuidString
            }
        }
    }

    private var terms: [String] { SearchMatch.terms(of: query) }

    private func matches(_ text: String) -> Bool {
        terms.allSatisfy { SearchMatch.wordStart(of: $0, in: text) != nil }
    }

    private var rows: [Row] {
        switch request.mode {
        case .commands:
            AppCommand.all(tabs: settings.visibleSidebarItems).filter { request.handlers[$0] != nil && matches($0.title) }.map(Row.command)
        case .search:
            searchRows.map(Row.record)
        case .project:
            ([nil] + projects).filter { matches($0?.name ?? "No Project") }.map(Row.project)
        case .join:
            meetings.filter { matches($0.title) }.map(Row.meeting)
        }
    }

    private var prompt: String {
        switch request.mode {
        case .commands: "Type a command"
        case .search(let kind?): "Search \(kind.label.lowercased())"
        case .search(nil): "Search everything"
        case .project: "Move to project"
        case .join: "Join a meeting"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            field
            let rows = rows
            if !rows.isEmpty {
                Divider()
                list(rows)
            }
        }
        .frame(width: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onAppear {
            isFieldFocused = true
            if request.mode == .join { meetings = CalendarEvent.joinableToday(in: modelContext) }
        }
        .onChange(of: query) { selectedIndex = 0 }
        .task(id: query) { await search() }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: fieldIcon)
                .foregroundStyle(.secondary)
            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($isFieldFocused)
                .onSubmit { run(selectedIndex) }
                .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in move(by: -1) }
                .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in move(by: 1) }
                .onKeyPress(.escape) {
                    onClose(nil)
                    return .handled
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func list(_ rows: [Row]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, isSelected: index == selectedIndex)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { run(index) }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 380)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: selectedIndex) { proxy.scrollTo(selectedIndex) }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row, isSelected: Bool) -> some View {
        switch row {
        case .record(let record):
            SearchResultRow(row: record, terms: terms, isSelected: isSelected)
        case .command(let command):
            label(command.title, systemImage: command.systemImage,
                  shortcut: command.shortcut(visibleTabs: settings.visibleSidebarItems)?.label, isSelected: isSelected)
        case .project(let project):
            label(project?.name ?? "No Project", systemImage: project?.icon ?? "xmark.circle", shortcut: nil, isSelected: isSelected)
        case .meeting(let event):
            label(event.title, systemImage: "video", shortcut: startLabel(event), isSelected: isSelected)
        }
    }

    private var fieldIcon: String {
        switch request.mode {
        case .commands: "command"
        case .join: "video"
        case .search, .project: "magnifyingglass"
        }
    }

    /// "Now" for one under way, else its start time.
    private func startLabel(_ event: CalendarEvent) -> String {
        event.startTime <= .now ? "Now" : event.startTime.formatted(date: .omitted, time: .shortened)
    }

    /// A row's icon, title and, on the right, its key or time.
    private func label(_ title: String, systemImage: String, shortcut: String?, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
            Spacer(minLength: 8)
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions

    private func move(by delta: Int) -> KeyPress.Result {
        let count = rows.count
        guard count > 0 else { return .handled }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
        return .handled
    }

    private func run(_ index: Int) {
        let rows = rows
        guard rows.indices.contains(index) else { return }
        switch rows[index] {
        case .command(let command):
            let handlers = request.handlers
            onClose { handlers.perform(command) }
        case .project(let project):
            let choose = request.chooseProject
            onClose { choose?(project) }
        case .record(let record):
            let query = query
            onClose { open(record, query: query) }
        case .meeting(let event):
            let url = event.meetingURL
            onClose { if let url { NSWorkspace.shared.open(url) } }
        }
    }

    /// Opens a hit as the Search tab does; log entries and PRs, which that tab expands in place,
    /// open the Search tab on this query.
    private func open(_ row: SearchRow, query: String) {
        switch row.result {
        case .person(let person): navigator.openPerson(person)
        case .feedback(let feedback): navigator.openPerson(feedback.person)
        case .meeting(let meeting): navigator.openMeeting(meeting)
        case .interview(let interview): navigator.openInterview(interview)
        case .todo(let todo): navigator.openTodo(todo)
        case .project(let project): navigator.openProject(project)
        case .log, .pr:
            navigator.searchQuery = query
            navigator.select(.search)
        }
    }

    /// Debounced; the text search runs on `Searcher`'s actor, then the hits are fetched here by id.
    private func search() async {
        guard case .search(let kind) = request.mode else { return }
        guard !terms.isEmpty else {
            searchRows = []
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        let hits = (try? await Searcher(modelContainer: modelContext.container).search(query)) ?? []
        guard !Task.isCancelled else { return }
        let matching = kind.map { kind in hits.filter { $0.kind == kind } } ?? hits
        searchRows = SearchRow.resolve(Array(matching.prefix(Self.searchLimit)), in: modelContext)
        selectedIndex = 0
    }
}
