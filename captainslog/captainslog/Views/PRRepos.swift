import AppKit
import SwiftUI
import CaptainsLogKit

/// The repos whose pull requests sync, above the Pull Requests list. They're added and removed here.
struct PRRepoBar: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @State private var adding = false

    var body: some View {
        FlowLayout(spacing: 6) {
            Text("Syncing")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 3)
            ForEach(settings.repos, id: \.self) { repo in
                RepoChip(repo: repo) {
                    settings.repos.removeAll { $0 == repo }
                    Task { await sync.reposChanged() }
                }
            }
            if adding {
                RepoField(compact: true, onDone: { adding = false })
            } else {
                Button { adding = true } label: {
                    Label("Add Repo", systemImage: "plus")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(.quaternary))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Sync another repo's pull requests")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RepoChip: View {
    let repo: String
    let remove: () -> Void

    private var url: URL? { URL(string: "https://github.com/\(repo)/pulls") }

    var body: some View {
        HStack(spacing: 4) {
            Text(repo)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stop syncing \(repo)")
        }
        .font(.caption)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 3)
        // Neutral, unlike the author chips below, which filter on a click.
        .background(.quinary, in: .capsule)
        .overlay(Capsule().strokeBorder(.quaternary))
        .contextMenu {
            if let url {
                Button("Open on GitHub") { NSWorkspace.shared.open(url) }
            }
            Button("Stop Syncing", action: remove)
        }
    }
}

/// Adds a repo, from its name or a pasted GitHub link. Used wherever setup asks for the first repo too.
struct RepoField: View {
    /// A chip-sized field that takes focus at once, for the repo bar.
    var compact = false
    var onDone: () -> Void = {}

    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @State private var draft = ""
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("org/repo or a GitHub link", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(compact ? .caption : .body)
                .frame(width: compact ? 200 : 260)
                .focused($focused)
                .onSubmit(add)
                .onExitCommand(perform: onDone)
                .onChange(of: draft) { problem = nil }
            Button("Add", action: add)
                .controlSize(compact ? .small : .regular)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            if compact {
                Button("Cancel", action: onDone)
                    .controlSize(.small)
                    .buttonStyle(.borderless)
            }
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear { if compact { focused = true } }
    }

    private func add() {
        guard let repo = GitHubRepo.parse(draft) else {
            problem = "Not a repo: use org/repo"
            return
        }
        if !settings.repos.contains(where: { $0.caseInsensitiveCompare(repo) == .orderedSame }) {
            settings.repos.append(repo)
            Task { await sync.reposChanged() }
        }
        draft = ""
        onDone()
    }
}
