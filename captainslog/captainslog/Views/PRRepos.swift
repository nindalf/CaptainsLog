import AppKit
import SwiftUI
import CaptainsLogKit

/// The repos whose pull requests sync, in the Pull Requests tab's toolbar. They're added and removed here.
struct PRRepoMenu: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var sync
    @State private var adding = false

    var body: some View {
        Menu {
            Section("Syncing") {
                ForEach(settings.repos, id: \.self) { repo in
                    Menu(repo) {
                        if let url = URL(string: "https://github.com/\(repo)/pulls") {
                            Button("Open on GitHub") { NSWorkspace.shared.open(url) }
                        }
                        Button("Stop Syncing") {
                            settings.repos.removeAll { $0 == repo }
                            Task { await sync.reposChanged() }
                        }
                    }
                }
            }
            Button("Add Repo…") { adding = true }
        } label: {
            Label("Repos", systemImage: "shippingbox")
        }
        .help("The repos whose pull requests sync")
        .popover(isPresented: $adding, arrowEdge: .bottom) {
            RepoField(compact: true, onDone: { adding = false })
                .padding(12)
        }
    }
}

/// Adds a repo, from its name or a pasted GitHub link. Used wherever setup asks for the first repo too.
struct RepoField: View {
    /// A small field that takes focus at once, for the repo menu's popover.
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
        .onAppear { if compact { DispatchQueue.main.async { focused = true } } }
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
