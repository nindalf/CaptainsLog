import SwiftUI
import SwiftData
import CaptainsLogKit

enum PRFocusField: Hashable {
    case list
    case notes(UUID)
}

struct PRListView: View {
    @Query(filter: #Predicate<PullRequest> { $0.stateRawValue == "open" }, sort: \PullRequest.createdAt, order: .reverse)
    private var openPRs: [PullRequest]
    @Query(filter: #Predicate<PullRequest> { $0.stateRawValue != "open" }, sort: \PullRequest.createdAt, order: .reverse)
    private var donePRs: [PullRequest]
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var navigator

    @State private var selectedID: UUID?
    @State private var expandedID: UUID?
    /// Team in Flight and Older show this many more each time.
    private static let page = 10

    @State private var teamLimit = page
    @State private var olderLimit = page
    @State private var showsShipped = false
    @State private var showsOlder = false
    @FocusState private var focusedField: PRFocusField?

    /// Open PRs by what they need from me, each section in the order it shows.
    private struct Sections {
        var needsMe: [Row]
        var waiting: [Row]
        var inFlight: [Row]
    }

    private var sections: Sections {
        let rows = openPRs.map { Row(pr: $0, attention: $0.attention()) }
        func since(_ row: Row) -> Date { row.attention.since(row.pr) }
        let needsMe = rows.filter { $0.attention.section == .needsMe }
            .sorted { ($0.attention.urgency, since($0)) < ($1.attention.urgency, since($1)) }
        // Stale first, then longest waiting.
        let waiting = rows.filter { $0.attention.section == .waiting }
            .sorted { ($0.attention.isStale ? 0 : 1, since($0)) < ($1.attention.isStale ? 0 : 1, since($1)) }
        // Stale first, then newest.
        let inFlight = rows.filter { $0.attention.section == .inFlight }
            .sorted { $0.attention.isStale != $1.attention.isStale ? $0.attention.isStale : since($0) > since($1) }
        return Sections(needsMe: needsMe, waiting: waiting, inFlight: inFlight)
    }

    /// Merged and closed PRs, newest first: this week's merges, then everything older.
    private var finished: (shipped: [Row], older: [Row]) {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let rows = donePRs
            .map { Row(pr: $0, attention: $0.state == .merged ? .merged : .closed) }
            .sorted { $0.attention.since($0.pr) > $1.attention.since($1.pr) }
        let shipped = rows.filter { $0.attention == .merged && $0.attention.since($0.pr) >= weekStart }
        let shippedIDs = Set(shipped.map(\.id))
        return (shipped, rows.filter { !shippedIDs.contains($0.id) })
    }

    /// The rows on screen, in order.
    private var shownRows: [Row] {
        let sections = sections
        let finished = finished
        return sections.needsMe + sections.waiting + sections.inFlight.prefix(teamLimit)
            + (showsShipped ? finished.shipped : [])
            + (showsOlder ? Array(finished.older.prefix(olderLimit)) : [])
    }

    var body: some View {
        // Setup stays outside the list, so its key handlers don't take a field's Return and arrows.
        VStack(spacing: 0) {
            if let setup, openPRs.isEmpty && donePRs.isEmpty {
                SetupInstructionView(instruction: setup)
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                if let setup {
                    SetupInstructionView(instruction: setup, style: .banner)
                        .contentColumn()
                        .padding(.top, 12)
                }
                prList
            }
        }
        .navigationTitle("Pull Requests")
        .toolbar { toolbarContent }
    }

    private var prList: some View {
        let sections = sections
        let (shipped, older) = finished
        return ScrollViewReader { proxy in ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                section("Needs You", sections.needsMe)
                section("Waiting on Others", sections.waiting)
                if !sections.inFlight.isEmpty {
                    Section {
                        ForEach(sections.inFlight.prefix(teamLimit)) { row in prRow(row) }
                        ShowMoreButton(remaining: sections.inFlight.count - teamLimit, pageSize: Self.page) { teamLimit += Self.page }
                            .padding(.horizontal, RecordRowMetrics.padding)
                    } header: {
                        sectionHeader("Team in Flight", count: sections.inFlight.count)
                    }
                }
                collapsibleSection("Shipped This Week", shipped, isExpanded: $showsShipped)
                collapsibleSection("Older", older, isExpanded: $showsOlder, limit: $olderLimit)
                if openPRs.isEmpty && donePRs.isEmpty {
                    emptyState
                        .padding(.top, 40)
                }
            }
            .contentColumn()
        }
        .onAppear { revealRequestedPR(proxy) }
        .onChange(of: navigator.revealRecordID) { revealRequestedPR(proxy) }
        }
        .contentShape(Rectangle())
        .onTapGesture { collapseCard() }
        .focusable()
        .focusEffectDisabled()
        .focused($focusedField, equals: .list)
        .onAppear { DispatchQueue.main.async { focusedField = .list } }
        .onKeyPress(.return, phases: .down) { handleReturn($0) }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in moveSelection(by: 1); return .handled }
        .animation(.snappy(duration: 0.18), value: expandedID)
        .selectionCommands(selectionCommands, claimsOnAppear: true, selection: [selectedID, expandedID]) {
            focusedField = .list
        }
    }

    private var selectionCommands: CommandHandlers {
        var handlers = CommandHandlers()
        if let pr = selectedPR {
            handlers[.openInGitHub] = { NSWorkspace.shared.open(pr.url) }
        }
        return handlers
    }

    /// Only while its row is on screen: a collapsed section or the Team in Flight limit can hide it.
    private var selectedPR: PullRequest? {
        guard let selectedID else { return nil }
        return shownRows.first { $0.pr.id == selectedID }?.pr
    }

    // MARK: - Sections

    struct Row: Identifiable {
        let pr: PullRequest
        let attention: PRAttention
        var id: UUID { pr.id }
    }

    private var setup: SetupInstruction? { SetupInstruction.github(syncCoordinator.githubSetup) }

    @ViewBuilder
    private func section(_ title: String, _ rows: [Row]) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in prRow(row) }
            } header: {
                sectionHeader(title, count: rows.count)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if syncCoordinator.githubSetup == .ready, syncCoordinator.history.sources[.github]?.lastSuccess == nil {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Syncing pull requests from \(settings.repos.formatted(.list(type: .and)))")
                    .foregroundStyle(.secondary)
            }
        } else {
            ContentUnavailableView("Nothing in Flight", systemImage: RecordKind.pullRequest.icon)
        }
    }

    /// Finished PRs, collapsed until their header is clicked. With a limit, a page at a time.
    @ViewBuilder
    private func collapsibleSection(_ title: String, _ rows: [Row], isExpanded: Binding<Bool>, limit: Binding<Int>? = nil) -> some View {
        if !rows.isEmpty {
            Section {
                if isExpanded.wrappedValue {
                    let shown = limit.map { rows.prefix($0.wrappedValue) } ?? rows[...]
                    ForEach(shown) { row in prRow(row) }
                    if let limit {
                        ShowMoreButton(remaining: rows.count - limit.wrappedValue, pageSize: Self.page) { limit.wrappedValue += Self.page }
                            .padding(.horizontal, RecordRowMetrics.padding)
                    }
                }
            } header: {
                Button {
                    withAnimation { isExpanded.wrappedValue.toggle() }
                } label: {
                    SectionHeader(title: title, count: rows.count, isExpanded: isExpanded.wrappedValue)
                        .pinnedSectionHeader()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        SectionHeader(title: title, count: count).pinnedSectionHeader()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !settings.repos.isEmpty {
            ToolbarItem { PRRepoMenu() }
        }
    }

    // MARK: - Row builder

    @ViewBuilder
    private func prRow(_ row: Row) -> some View {
        if expandedID == row.pr.id {
            PRCardView(pr: row.pr, focusedField: $focusedField, onCollapse: { collapseCard() })
                .padding(.vertical, 2)
                .contextMenu { PRContextMenu(pr: row.pr) }
        } else {
            PRRecordRow(pr: row.pr, attention: row.attention, isSelected: selectedID == row.pr.id)
                .onRecordClick(select: {
                    if selectedID != row.pr.id { collapseCard() }
                    selectedID = row.pr.id
                }, open: { expandPR(row.pr) })
                .contextMenu { PRContextMenu(pr: row.pr) }
        }
    }

    // MARK: - Expand / collapse

    /// A PR opened from elsewhere: its section opened far enough to show it, expanded and scrolled to.
    private func revealRequestedPR(_ proxy: ScrollViewProxy) {
        guard let id = navigator.revealRecordID else { return }
        let sections = sections
        let (shipped, older) = finished
        if let index = sections.inFlight.firstIndex(where: { $0.id == id }) {
            teamLimit = max(teamLimit, (index / Self.page + 1) * Self.page)
        } else if shipped.contains(where: { $0.id == id }) {
            showsShipped = true
        } else if let index = older.firstIndex(where: { $0.id == id }) {
            showsOlder = true
            olderLimit = max(olderLimit, (index / Self.page + 1) * Self.page)
        } else if !(sections.needsMe + sections.waiting).contains(where: { $0.id == id }) {
            return
        }
        navigator.revealRecordID = nil
        guard let pr = (openPRs + donePRs).first(where: { $0.id == id }) else { return }
        expandPR(pr)
        // After the section it opened has laid out its rows.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation { proxy.scrollTo(id, anchor: .center) }
        }
    }

    private func expandPR(_ pr: PullRequest) {
        selectedID = pr.id
        expandedID = pr.id
        focusedField = .notes(pr.id)
    }

    private func collapseCard() {
        expandedID = nil
        focusedField = .list
    }

    // MARK: - Selection

    private func moveSelection(by delta: Int) {
        let ids = shownRows.map(\.pr.id)
        guard !ids.isEmpty else { return }
        if let selectedID, let index = ids.firstIndex(of: selectedID) {
            let newIndex = max(0, min(ids.count - 1, index + delta))
            self.selectedID = ids[newIndex]
        } else {
            selectedID = delta > 0 ? ids.first : ids.last
        }
    }

    // MARK: - Key handlers

    private func handleReturn(_ keyPress: KeyPress) -> KeyPress.Result {
        if keyPress.modifiers.contains(.shift) { return .ignored }
        if expandedID != nil {
            collapseCard()
            return .handled
        }
        guard let pr = selectedPR else { return .ignored }
        expandPR(pr)
        return .handled
    }

    private func handleEscape() -> KeyPress.Result {
        if expandedID != nil {
            collapseCard()
            return .handled
        }
        return .ignored
    }
}

// MARK: - Context menu

struct PRContextMenu: View {
    let pr: PullRequest
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button("Open in GitHub") {
            NSWorkspace.shared.open(pr.url)
        }
        if !pr.isMine {
            Button("Add a Todo to Review") { addReviewTodo() }
        }
    }

    private func addReviewTodo() {
        let open = (try? modelContext.fetch(FetchDescriptor<Todo>(predicate: #Predicate { $0.completedDate == nil }))) ?? []
        let todo = ReviewTodo.make(for: pr, among: open)
        modelContext.insert(todo)
        todo.pullRequest = pr
        try? modelContext.save()
    }
}

// MARK: - Expanded card

/// A PR's row, unchanged, with its details and notes below.
struct PRCardView: View {
    @Bindable var pr: PullRequest
    var focusedField: FocusState<PRFocusField?>.Binding
    var onCollapse: () -> Void
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    private var notesBinding: Binding<String> {
        Binding(
            get: { pr.notes ?? "" },
            set: { pr.notes = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PRRecordRow(pr: pr)
            details
                .padding(.leading, RecordRowMetrics.titleInset)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
        }
        .recordCard()
        .contentShape(Rectangle())
        .onTapGesture { }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(pr.repo)
                CopyablePRNumber(pr: pr)
                GitHubButton(pr: pr)
                Text(DateLabel.day(pr.createdAt))
                if let merged = pr.mergedAt {
                    Text("Merged \(DateLabel.day(merged, inSentence: true))")
                }
                if let additions = pr.additions, let deletions = pr.deletions {
                    ChangeStats(additions: additions, deletions: deletions)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let body = pr.body,
               !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .textSelection(.enabled)
            }

            if pr.author != nil || !pr.reviewers.isEmpty {
                HStack(spacing: 12) {
                    if let author = pr.author {
                        Label(author.name, systemImage: "person")
                    }
                    if !pr.reviewers.isEmpty {
                        Label(pr.reviewers.map(\.name).joined(separator: ", "), systemImage: "person.2")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            TextEditor(text: notesBinding)
                .font(.body)
                .foregroundStyle(.secondary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 20, maxHeight: 120)
                .focused(focusedField, equals: .notes(pr.id))
                .overlay(alignment: .topLeading) {
                    if (pr.notes ?? "").isEmpty {
                        Text("Notes")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                            .allowsHitTesting(false)
                    }
                }
                .onKeyPress(.return, phases: .down) { keyPress in
                    if keyPress.modifiers.contains(.shift) { return .ignored }
                    onCollapse()
                    return .handled
                }

            HStack {
                Spacer(minLength: 0)
                ProjectControl(current: pr.project, projects: projects) { pr.project = $0 }
            }
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared views

/// The GitHub mark as a button that opens the pull request in the browser. An asset rather than an
/// SF Symbol, so it doesn't follow the font: the default size matches a caption.
struct GitHubButton: View {
    let pr: PullRequest
    var size: CGFloat = 11

    var body: some View {
        Button { NSWorkspace.shared.open(pr.url) } label: {
            Image("GitHubMark")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Open #\(pr.number) on GitHub")
    }
}

struct CopyablePRNumber: View {
    let pr: PullRequest
    @State private var showCopied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
            showCopied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showCopied = false
            }
        } label: {
            Text(verbatim: showCopied ? "Copied!" : "#\(pr.number)")
                .font(.caption)
                .foregroundStyle(showCopied ? Color.green : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("Copy GitHub link")
    }
}

struct ChangeStats: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: 2) {
            Text("+\(additions)")
                .foregroundStyle(.green)
            Text("-\(deletions)")
                .foregroundStyle(.red)
        }
        .font(.caption.monospacedDigit())
    }
}

#Preview {
    NavigationStack {
        PRListView()
    }
    .previewEnvironment()
}
