import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import CaptainsLogKit

/// A roster read from disk and what importing it would do.
struct RosterImportPreview: Identifiable {
    let id = UUID()
    let fileName: String
    let entries: [RosterEntry]
    let rows: [RosterImportRow]

    /// Asks for a file and plans its import. Nil when the panel is cancelled.
    @MainActor
    static func choose(in context: ModelContext) throws -> RosterImportPreview? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a roster: a JSON array of {name, email, github, slack}"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let entries = try Roster.decode(Data(contentsOf: url))
        let people = try context.fetch(FetchDescriptor<Person>())
        return RosterImportPreview(
            fileName: url.lastPathComponent,
            entries: entries,
            rows: Roster.plan(entries, against: people)
        )
    }
}

struct RosterImportSheet: View {
    let preview: RosterImportPreview

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private func rows(_ action: RosterImportRow.Action) -> [RosterImportRow] {
        preview.rows.filter { $0.action == action }
    }

    private var unchangedWithConflicts: [RosterImportRow] {
        rows(.unchanged).filter { !$0.conflicts.isEmpty }
    }

    private var upToDateCount: Int {
        rows(.unchanged).count - unchangedWithConflicts.count
    }

    private var hasChanges: Bool {
        preview.rows.contains { $0.action == .create || $0.action == .update }
    }

    var body: some View {
        NavigationStack {
            List {
                section("New", rows(.create))
                section("Updated", rows(.update))
                section("Kept what's stored", unchangedWithConflicts)
                section("Skipped", rows(.skip))
                if upToDateCount > 0 {
                    Text("\(upToDateCount) already up to date.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import \(preview.fileName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: apply)
                        .disabled(!hasChanges)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 480)
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [RosterImportRow]) -> some View {
        if !rows.isEmpty {
            Section("\(title) (\(rows.count))") {
                ForEach(rows) { RosterImportRowView(row: $0) }
            }
        }
    }

    private func apply() {
        // Planned again, so anything sync changed since the preview is taken into account.
        guard let people = try? modelContext.fetch(FetchDescriptor<Person>()) else { return }
        Roster.apply(preview.entries, to: people, in: modelContext)
        try? modelContext.save()
        dismiss()
    }
}

private struct RosterImportRowView: View {
    let row: RosterImportRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.personName ?? row.entry.name).font(.headline)
            if row.action == .create {
                detail(identifiers)
            }
            if !row.merged.isEmpty {
                detail("Merges in " + row.merged.map(\.name).joined(separator: ", "))
            }
            if !row.filled.isEmpty {
                detail("Adds " + row.filled.map { "\(label($0.field)) \($0.value)" }.joined(separator: ", "))
            }
            ForEach(row.conflicts, id: \.self) { conflict in
                detail("Keeps \(label(conflict.field)) \(conflict.stored), not \(conflict.roster)")
                    .foregroundStyle(.orange)
            }
            if let reason = row.skipReason {
                detail(reason)
            }
        }
        .padding(.vertical, 2)
    }

    private var identifiers: String {
        [row.entry.email, row.entry.github.map { "@\($0)" }, row.entry.slack.map { "@\($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func label(_ field: RosterField) -> String {
        switch field {
        case .name: "name"
        case .email: "email"
        case .github: "GitHub"
        case .slack: "Slack"
        }
    }
}

/// Pick people, then save them as a roster. Starts with the people whose PRs are synced.
struct RosterExportSheet: View {
    @Query(sort: \Person.name) private var allPeople: [Person]
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID> = []
    @State private var includeCalendarOnly = false
    @State private var searchText = ""
    @State private var error: String?

    private var candidates: [Person] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        return allPeople.filter { person in
            guard person.email != nil || person.githubHandle != nil || person.slackHandle != nil else { return false }
            guard includeCalendarOnly || person.isMeaningfulContact else { return false }
            guard !trimmed.isEmpty else { return true }
            return [person.name, person.email, person.githubHandle, person.slackHandle]
                .contains { $0?.localizedCaseInsensitiveContains(trimmed) ?? false }
        }
    }

    var body: some View {
        NavigationStack {
            List(candidates) { person in
                Toggle(isOn: Binding(
                    get: { selected.contains(person.id) },
                    set: { isOn in
                        if isOn { selected.insert(person.id) } else { selected.remove(person.id) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                        Text(handles(person))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .searchable(text: $searchText, prompt: "Search people")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Select All") { selected.formUnion(candidates.map(\.id)) }
                    Button("Select None") { selected.subtract(candidates.map(\.id)) }
                    Toggle("Calendar-only people", isOn: $includeCalendarOnly)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Text("\(selected.count) selected")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.bar)
            }
            .navigationTitle("Export Roster")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export…", action: export)
                        .disabled(selected.isEmpty)
                }
            }
            .alert("Couldn't Export", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(error ?? "")
            }
        }
        .frame(minWidth: 460, minHeight: 520)
        .onAppear {
            selected = Set(allPeople.filter(\.syncsPullRequests).map(\.id))
        }
    }

    private func handles(_ person: Person) -> String {
        [person.email, person.githubHandle.map { "@\($0)" }, person.slackHandle.map { "@\($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "roster.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let people = allPeople.filter { selected.contains($0.id) }
            try Roster.encode(Roster.entries(for: people)).write(to: url, options: .atomic)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
