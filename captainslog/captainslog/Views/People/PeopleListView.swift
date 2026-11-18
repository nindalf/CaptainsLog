import SwiftUI
import SwiftData
import CaptainsLogKit

struct PeopleListView: View {
    @Query(sort: \Person.name) private var allPeople: [Person]
    @State private var searchText = ""
    @Environment(\.modelContext) private var modelContext
    @State private var rosterImport: RosterImportPreview?
    @State private var showRosterExport = false
    @State private var rosterError: String?
    @State private var showAddPerson = false
    @State private var selectedID: UUID?
    @FocusState private var listFocused: Bool
    @Environment(Navigator.self) private var navigator

    private var people: [Person] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return allPeople
            .filter { person in
                guard person.isMeaningfulContact else { return false }
                guard !trimmed.isEmpty else { return true }
                return person.name.lowercased().contains(trimmed)
                    || (person.email?.lowercased().contains(trimmed) ?? false)
                    || (person.githubHandle?.lowercased().contains(trimmed) ?? false)
                    || (person.slackHandle?.lowercased().contains(trimmed) ?? false)
            }
            .sorted { lhs, rhs in
                if lhs.activityScore != rhs.activityScore {
                    return lhs.activityScore > rhs.activityScore
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        Group {
            if people.isEmpty {
                ContentUnavailableView {
                    Label(searchText.isEmpty ? "No People" : "No Matches", systemImage: "person.2")
                } description: {
                    Text(searchText.isEmpty
                        ? "People you add, or who are linked to a meeting, PR or feedback, appear here."
                        : "No one matches \"\(searchText)\".")
                } actions: {
                    if searchText.isEmpty {
                        Button("Add Person…") { showAddPerson = true }
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(people) { person in
                            PersonRow(person: person)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedID == person.id ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
                                .contentShape(Rectangle())
                                .onRecordClick(select: { selectedID = person.id }, open: { open(person) })
                        }
                    }
                    .contentColumn()
                    .padding(.vertical, 8)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .onAppear { DispatchQueue.main.async { listFocused = true } }
                .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in moveSelection(by: -1); return .handled }
                .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in moveSelection(by: 1); return .handled }
                .onKeyPress(.return, phases: .down) { _ in openSelected() }
                .selectionCommands(CommandHandlers(), claimsOnAppear: true, selection: selectedID) { listFocused = true }
            }
        }
        .navigationTitle("People")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search people")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Import Roster…", action: chooseRoster)
                    Button("Export Roster…") { showRosterExport = true }
                } label: {
                    Label("Roster", systemImage: "person.2.badge.plus")
                }
                .help("Import or export a roster of emails and GitHub and Slack handles")
            }
            ToolbarItem {
                Button("Add Person", systemImage: "plus") { showAddPerson = true }
                    .help(AppCommand.addPerson.help("Add Person"))
            }
        }
        .sheet(item: $rosterImport) { RosterImportSheet(preview: $0) }
        .sheet(isPresented: $showRosterExport) { RosterExportSheet() }
        .sheet(isPresented: $showAddPerson) { AddPersonSheet { navigator.openPerson($0) } }
        .focusedSceneValue(\.tabCommands, tabCommands)
        .alert("Couldn't Read Roster", isPresented: Binding(
            get: { rosterError != nil },
            set: { if !$0 { rosterError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(rosterError ?? "")
        }
    }

    private var tabCommands: CommandHandlers {
        var handlers = CommandHandlers()
        handlers[.addPerson] = { showAddPerson = true }
        handlers[.importRoster] = { chooseRoster() }
        handlers[.exportRoster] = { showRosterExport = true }
        return handlers
    }

    private func moveSelection(by delta: Int) {
        selectedID = movedSelection(selectedID, by: delta, in: people.map(\.id))
    }

    private func openSelected() -> KeyPress.Result {
        guard let person = people.first(where: { $0.id == selectedID }) else { return .ignored }
        open(person)
        return .handled
    }

    private func open(_ person: Person) {
        selectedID = person.id
        navigator.openPerson(person)
    }

    private func chooseRoster() {
        do {
            rosterImport = try RosterImportPreview.choose(in: modelContext)
        } catch {
            rosterError = error.localizedDescription
        }
    }
}

private struct PersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 10) {
            PersonAvatar(name: person.name)
            VStack(alignment: .leading, spacing: 3) {
                Text(person.name).font(.headline)
                if let subtitle = handleLine {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let summary = associationSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var handleLine: String? {
        let parts = [
            person.email,
            person.githubHandle.map { "@\($0)" },
            person.slackHandle.map { "@\($0)" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var associationSummary: String? {
        var parts: [String] = []
        let meetings = (person.meetings ?? []).count
        let prs = (person.authoredPRs ?? []).count + (person.reviewedPRs ?? []).count
        let feedback = (person.feedback ?? []).count
        if meetings > 0 { parts.append("\(meetings) meeting\(meetings == 1 ? "" : "s")") }
        if prs > 0 { parts.append("\(prs) PR\(prs == 1 ? "" : "s")") }
        if feedback > 0 { parts.append("\(feedback) feedback") }
        let interviews = (person.interviews ?? []).count
        if interviews > 0 { parts.append("\(interviews) interview\(interviews == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        PeopleListView()
    }
    .previewEnvironment()
}
