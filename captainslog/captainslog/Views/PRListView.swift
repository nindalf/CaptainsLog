import SwiftUI
import SwiftData
import CaptainsLogKit

enum PRFocusField: Hashable {
    case list
    case notes(UUID)
}

struct PRListView: View {
    @Query(sort: \PullRequest.createdAt, order: .reverse)
    private var allPRs: [PullRequest]
    @Query(filter: #Predicate<Person> { $0.syncsPullRequests }, sort: \Person.name)
    private var syncedPeople: [Person]
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(AppSettings.self) private var settings

    @State private var stateFilter: PRState?
    @State private var showAll = false
    @State private var selectedID: UUID?
    @State private var expandedID: UUID?
    @State private var reviewRequestLimit = 5
    @State private var teammateLimit = 5
    @FocusState private var focusedField: PRFocusField?

    /// The PRs the state filter and the older-PRs cutoff let through, before hiding anyone.
    private var scopedPRs: [PullRequest] {
        var prs = allPRs
        if let stateFilter {
            prs = prs.filter { $0.state == stateFilter }
        }
        if !showAll && stateFilter == nil {
            let cutoff = Self.recentCutoff
            prs = prs.filter { Self.isRecent($0, cutoff: cutoff) }
        }
        return prs
    }

    private var visiblePRs: [PullRequest] {
        scopedPRs.filter { !settings.isHidden($0) }
    }

    private var myPRs: [PullRequest] {
        visiblePRs.filter { $0.isAuthoredByMe && $0.state != .closed }
    }

    private var allReviewRequests: [PullRequest] {
        visiblePRs.filter { $0.isReviewRequest && !$0.isDraft }
    }

    private var shownReviewRequests: [PullRequest] {
        Array(allReviewRequests.prefix(reviewRequestLimit))
    }

    private var allTeammatePRs: [PullRequest] {
        visiblePRs.filter(\.isTeammateOnly)
    }

    private var shownTeammatePRs: [PullRequest] {
        Array(allTeammatePRs.prefix(teammateLimit))
    }

    private var flatIDs: [UUID] {
        myPRs.map(\.id) + shownReviewRequests.map(\.id) + shownTeammatePRs.map(\.id)
    }

    private var hiddenCount: Int {
        guard !showAll, stateFilter == nil else { return 0 }
        let cutoff = Self.recentCutoff
        return allPRs.filter { !settings.isHidden($0) && !Self.isRecent($0, cutoff: cutoff) }.count
    }

    /// Everyone whose PRs are synced: people synced by choice, and the authors of the review
    /// requests and teammates' PRs in scope, hidden or not.
    private var authors: [PRAuthorChip.Author] {
        var counts: [UUID: Int] = [:]
        var people: [UUID: Person] = [:]
        for pr in scopedPRs where pr.isTeammateOnly || (pr.isReviewRequest && !pr.isDraft) {
            guard let author = pr.author else { continue }
            counts[author.id, default: 0] += 1
            people[author.id] = author
        }
        for person in syncedPeople {
            people[person.id] = person
        }
        return people.values
            .map { PRAuthorChip.Author(person: $0, count: counts[$0.id] ?? 0) }
            .sorted {
                if $0.person.syncsPullRequests != $1.person.syncsPullRequests { return $0.person.syncsPullRequests }
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.person.name.localizedStandardCompare($1.person.name) == .orderedAscending
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                if let setup, !allPRs.isEmpty {
                    SetupInstructionView(instruction: setup, style: .banner)
                        .padding(.top, 12)
                } else if syncCoordinator.history.sources[.github]?.isFailing == true {
                    SyncStatusLabel(source: .github)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                        .padding(.horizontal, 4)
                }
                if !authors.isEmpty {
                    authorFilter
                }
                if !myPRs.isEmpty {
                    Section {
                        ForEach(myPRs) { pr in prRow(for: pr) }
                    } header: {
                        sectionHeader("My PRs")
                    }
                }
                if !allReviewRequests.isEmpty {
                    Section {
                        ForEach(shownReviewRequests) { pr in prRow(for: pr) }
                        moreButton(allReviewRequests.count - reviewRequestLimit, "review request") {
                            reviewRequestLimit += 5
                        }
                    } header: {
                        sectionHeader("Review Requests")
                    }
                }
                if !allTeammatePRs.isEmpty {
                    Section {
                        ForEach(shownTeammatePRs) { pr in prRow(for: pr) }
                        moreButton(allTeammatePRs.count - teammateLimit, "PR") {
                            teammateLimit += 5
                        }
                    } header: {
                        sectionHeader("Teammates")
                    }
                }
                if hiddenCount > 0 {
                    Button {
                        withAnimation { showAll = true }
                    } label: {
                        Label(
                            "\(hiddenCount) older pull request\(hiddenCount == 1 ? "" : "s")",
                            systemImage: "clock.arrow.circlepath"
                        )
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
                if visiblePRs.isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else if setup == nil, syncCoordinator.history.sources[.github]?.isFailing != true {
                    SyncStatusLabel(source: .github)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { collapseCard() }
        .focusable()
        .focusEffectDisabled()
        .focused($focusedField, equals: .list)
        .onAppear { focusedField = .list }
        .onKeyPress(.return, phases: .down) { handleReturn($0) }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in moveSelection(by: 1); return .handled }
        .navigationTitle("Pull Requests")
        .toolbar { toolbarContent }
        .animation(.snappy(duration: 0.18), value: expandedID)
    }

    // MARK: - Sections

    private var setup: SetupInstruction? { SetupInstruction.github(syncCoordinator.githubSetup) }

    @ViewBuilder
    private var emptyState: some View {
        if let setup, allPRs.isEmpty {
            SetupInstructionView(instruction: setup)
        } else if syncCoordinator.githubSetup == .ready, syncCoordinator.history.sources[.github]?.lastSuccess == nil {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Syncing pull requests from \(settings.repos.formatted(.list(type: .and)))")
                    .foregroundStyle(.secondary)
            }
        } else {
            ContentUnavailableView {
                Label("No Pull Requests", systemImage: "arrow.triangle.pull")
            } description: {
                if syncCoordinator.history.sources[.github]?.isFailing != true {
                    SyncStatusLabel(source: .github)
                }
            }
        }
    }

    private var authorFilter: some View {
        FlowLayout(spacing: 6) {
            ForEach(authors, id: \.person.id) { author in
                PRAuthorChip(author: author)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func moreButton(_ count: Int, _ noun: String, action: @escaping () -> Void) -> some View {
        if count > 0 {
            Button {
                withAnimation { action() }
            } label: {
                Text("\(count) more \(noun)\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .padding(.horizontal, 4)
            .background(.background)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button {
                syncCoordinator.syncNow()
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(syncCoordinator.isSyncing)
        }
        ToolbarItem {
            Picker("State", selection: $stateFilter) {
                Text("All").tag(PRState?.none)
                ForEach(PRState.allCases, id: \.self) { state in
                    Text(state.rawValue.capitalized).tag(PRState?.some(state))
                }
            }
        }
    }

    // MARK: - Row builder

    @ViewBuilder
    private func prRow(for pr: PullRequest) -> some View {
        if expandedID == pr.id {
            PRCardView(pr: pr, focusedField: $focusedField, onCollapse: { collapseCard() })
                .padding(.vertical, 2)
                .contextMenu { PRContextMenu(pr: pr) }
        } else {
            PRCollapsedRow(pr: pr, isSelected: selectedID == pr.id)
                .onTapGesture {
                    if selectedID == pr.id {
                        expandPR(pr)
                    } else {
                        collapseCard()
                        selectedID = pr.id
                    }
                }
                .contextMenu { PRContextMenu(pr: pr) }
        }
    }

    // MARK: - Expand / collapse

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
        let ids = flatIDs
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
        guard let selectedID else { return .ignored }
        guard let pr = visiblePRs.first(where: { $0.id == selectedID }) else { return .ignored }
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

    // MARK: - Cutoff

    private static func isRecent(_ pr: PullRequest, cutoff: Date) -> Bool {
        switch pr.state {
        case .open:
            true
        case .merged:
            (pr.mergedAt ?? pr.createdAt) >= cutoff
        case .closed:
            pr.createdAt >= cutoff
        }
    }

    private static var recentCutoff: Date {
        let calendar = Calendar.current
        var date = calendar.startOfDay(for: .now)
        var weekdays = 0
        while weekdays < 5 {
            date = calendar.date(byAdding: .day, value: -1, to: date)!
            let weekday = calendar.component(.weekday, from: date)
            if weekday != 1 && weekday != 7 {
                weekdays += 1
            }
        }
        return date
    }
}

// MARK: - Author filter

/// One person whose PRs are synced. Clicking hides or shows their PRs; the right-click menu turns
/// syncing all their PRs on or off.
struct PRAuthorChip: View {
    struct Author {
        let person: Person
        let count: Int
    }

    let author: Author
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(\.modelContext) private var modelContext

    private var handle: String? { author.person.githubHandle }

    private var isHidden: Bool {
        handle.map(settings.hiddenPRAuthors.contains) ?? false
    }

    var body: some View {
        Button(action: toggleHidden) {
            HStack(spacing: 4) {
                if author.person.syncsPullRequests {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                }
                Text(author.person.name)
                    .strikethrough(isHidden)
                Text("\(author.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isHidden ? Color.clear : Color.accentColor.opacity(0.12), in: .capsule)
            .overlay(Capsule().strokeBorder(.quaternary))
            .foregroundStyle(isHidden ? .secondary : .primary)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(handle == nil)
        .help(help)
        .contextMenu {
            Toggle("Sync All Their PRs", isOn: Binding(
                get: { author.person.syncsPullRequests },
                set: { newValue in
                    author.person.syncsPullRequests = newValue
                    if newValue {
                        try? modelContext.save()
                        syncCoordinator.syncGitHubNow()
                    }
                }
            ))
        }
    }

    private var help: String {
        let what = author.person.syncsPullRequests
            ? "All of \(author.person.name)'s PRs sync"
            : "\(author.person.name)'s review requests sync"
        return "\(what). Click to \(isHidden ? "show" : "hide") them."
    }

    private func toggleHidden() {
        guard let handle else { return }
        if isHidden {
            settings.hiddenPRAuthors.removeAll { $0 == handle }
        } else {
            settings.hiddenPRAuthors.append(handle)
        }
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
        if !pr.isAuthoredByMe {
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

struct PRCardView: View {
    @Bindable var pr: PullRequest
    var focusedField: FocusState<PRFocusField?>.Binding
    var onCollapse: () -> Void

    private var notesBinding: Binding<String> {
        Binding(
            get: { pr.notes ?? "" },
            set: { pr.notes = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PRStatusBadge(status: pr.displayStatus)
                Link(pr.title, destination: pr.url)
                    .font(.headline)
            }

            HStack(spacing: 6) {
                Text(pr.repo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CopyablePRNumber(pr: pr)
            }

            HStack(spacing: 8) {
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
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { }
    }
}

// MARK: - Collapsed row

struct PRCollapsedRow: View {
    let pr: PullRequest
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                PRStatusBadge(status: pr.displayStatus)
                Text(pr.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            HStack {
                Text(pr.repo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CopyablePRNumber(pr: pr)
                if let author = pr.author, !pr.isAuthoredByMe {
                    Text(author.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let additions = pr.additions, let deletions = pr.deletions {
                    ChangeStats(additions: additions, deletions: deletions)
                }
                Text(DateLabel.day(pr.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Shared views

struct PRStatusBadge: View {
    let status: PRDisplayStatus

    private static let badgeWidth: CGFloat = 80

    var body: some View {
        Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(width: Self.badgeWidth)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .draft: "Draft"
        case .open: "Open"
        case .changesRequested: "Changes Requested"
        case .approved: "Approved"
        case .closed: "Closed"
        case .merged: "Merged"
        case .staging: "Staging"
        case .prod: "Prod"
        }
    }

    private var color: Color {
        switch status {
        case .draft: .gray
        case .open: .green
        case .changesRequested: .orange
        case .approved: .mint
        case .closed: .red
        case .merged: .purple
        case .staging: .blue
        case .prod: .teal
        }
    }
}

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
