import SwiftUI
import SwiftData
import CaptainsLogKit

/// The command palette, and the same box searching records, choosing a project or choosing one of
/// today's meetings to join or open. Floats over the window. Return runs the selected row; Escape
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
    @State private var meetings = TodaysMeetings(among: [], for: .join)
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
        case .meetings:
            meetings.events.filter { matches($0.title) }.map(Row.meeting)
        }
    }

    private var prompt: String {
        switch request.mode {
        case .commands: "Type a command"
        case .search(let kind?): "Search \(kind.label.lowercased())"
        case .search(nil): "Search everything"
        case .project: "Move to project"
        case .meetings(.join): "Join a meeting"
        case .meetings(.notes): "Open a meeting"
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
            // Next turn, once the field is in the window. Asked for in this update, focus moves
            // between the field and the window a few times and can stop on the window.
            DispatchQueue.main.async { isFieldFocused = true }
            if case .meetings(let purpose) = request.mode {
                meetings = TodaysMeetings(in: modelContext, for: purpose)
                selectedIndex = meetings.selected ?? 0
            }
        }
        // Clearing the query goes back to the selected meeting.
        .onChange(of: query) { selectedIndex = query.isEmpty ? meetings.selected ?? 0 : 0 }
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
            .onAppear { proxy.scrollTo(selectedIndex, anchor: .center) }
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
            label(event.title, systemImage: fieldIcon, shortcut: startLabel(event), isSelected: isSelected)
        }
    }

    private var fieldIcon: String {
        switch request.mode {
        case .commands: "command"
        case .meetings(.join): AppCommand.join.systemImage
        case .meetings(.notes): AppCommand.openMeeting.systemImage
        case .search, .project: "magnifyingglass"
        }
    }

    /// "Now" for one under way, else its start time, with the day when it isn't today.
    private func startLabel(_ event: CalendarEvent) -> String {
        let now = Date.now
        if event.startTime <= now && event.endTime > now { return "Now" }
        let time = event.startTime.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(event.startTime) ? time : "\(event.startTime.formatted(.dateTime.weekday(.abbreviated))) \(time)"
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
            onClose { open(record) }
        case .meeting(let event):
            if request.mode == .meetings(.notes) {
                onClose { open(event) }
            } else {
                let url = event.meetingURL
                onClose { if let url { NSWorkspace.shared.open(url) } }
            }
        }
    }

    /// Opens the event's meeting or interview, making a meeting first if it has neither, as the
    /// event popover's Add Notes does.
    private func open(_ event: CalendarEvent) {
        if event.meeting == nil && event.interview == nil {
            event.createMeeting(in: modelContext)
            try? modelContext.save()
        }
        navigator.openEvent(event)
    }

    /// Opens a hit as a link does: a page record's page, or a log entry or PR on its own tab.
    private func open(_ row: SearchRow) {
        switch row.result {
        case .person(let person): navigator.openPerson(person)
        case .feedback(let feedback): navigator.openPerson(feedback.person)
        case .meeting(let meeting): navigator.openMeeting(meeting)
        case .interview(let interview): navigator.openInterview(interview)
        case .todo(let todo): navigator.openTodo(todo)
        case .project(let project): navigator.openProject(project)
        case .log(let entry): navigator.openLogEntry(entry)
        case .pr(let pr): navigator.openPullRequest(pr)
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
