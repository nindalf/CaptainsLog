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
                ContentUnavailableView(
                    searchText.isEmpty ? "No People" : "No Matches",
                    systemImage: "person.2",
                    description: Text(searchText.isEmpty
                        ? "People appear here once they're linked to a meeting, PR, or feedback."
                        : "No one matches \"\(searchText)\".")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(people) { person in
                            NavigationRow(value: person) {
                                PersonRow(person: person)
                            }
                        }
                    }
                    .contentColumn()
                    .padding(.vertical, 8)
                }
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
        }
        .sheet(item: $rosterImport) { RosterImportSheet(preview: $0) }
        .sheet(isPresented: $showRosterExport) { RosterExportSheet() }
        .alert("Couldn't Read Roster", isPresented: Binding(
            get: { rosterError != nil },
            set: { if !$0 { rosterError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(rosterError ?? "")
        }
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
                        .foregroundStyle(.tertiary)
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
