import AppKit
import SwiftUI
import CaptainsLogKit

/// The one thing to do next to set up a sync source. Terminal steps open a browser, so the app shows
/// the command to paste rather than running it, and rechecks when it comes back to the front.
struct SetupInstruction {
    let title: String
    let message: String
    var command: String?
    /// Asks for a repo in place, instead of giving a command.
    var addsRepo = false

    static func github(_ setup: SourceSetup?) -> SetupInstruction? {
        switch setup {
        case .notInstalled:
            SetupInstruction(
                title: "Install the GitHub CLI",
                message: "Pull requests sync through gh. Install it with Homebrew:",
                command: "brew install gh")
        case .notLoggedIn:
            SetupInstruction(
                title: "Log in to GitHub",
                message: "Run this in Terminal. Pick GitHub.com, then log in with a browser.",
                command: "gh auth login")
        case .notConfigured:
            SetupInstruction(
                title: "Choose a repo to sync",
                message: "Add a repo whose pull requests you want to follow. You can add more later at the top of the Pull Requests tab.",
                addsRepo: true)
        case .missingScope, .ready, nil:
            nil
        }
    }

    static func calendar(_ setup: SourceSetup?) -> SetupInstruction? {
        switch setup {
        case .notInstalled:
            SetupInstruction(
                title: "Install the Google Workspace CLI",
                message: "Your calendar syncs through gws. Install it with Homebrew; `brew install gws` is an unrelated tool.",
                command: "brew install googleworkspace-cli")
        case .notLoggedIn:
            SetupInstruction(
                title: "Log in to Google Calendar",
                message: "Fill in your company's client ID and secret, then run this in Terminal. A browser opens: pick your work account. \"Access blocked\" means you picked a personal one.",
                command: calendarLogin)
        case .missingScope:
            SetupInstruction(
                title: "Let gws read your calendar",
                message: "gws is logged in without calendar access. Log in again with your company's client ID and secret; this replaces gws's current login.",
                command: calendarLogin)
        case .notConfigured, .ready, nil:
            nil
        }
    }

    /// Read-only, calendar only. gws saves the client with the token, so it's passed only this once.
    private static let calendarLogin = """
        GOOGLE_WORKSPACE_CLI_CLIENT_ID=<client-id> \\
        GOOGLE_WORKSPACE_CLI_CLIENT_SECRET=<client-secret> \\
        gws auth login --readonly -s calendar
        """
}

/// A setup step: centered in an empty tab, as a banner over a tab that still has older data,
/// or inline under a Dashboard checklist step, which shows the title itself.
struct SetupInstructionView: View {
    enum Style { case centered, banner, inline }

    let instruction: SetupInstruction
    var style = Style.centered

    private var centered: Bool { style == .centered }

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 10) {
            if style != .inline {
                Text(instruction.title)
                    .font(centered ? .title3.weight(.semibold) : .headline)
            }
            Text(instruction.message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(centered ? .center : .leading)
            if let command = instruction.command {
                CommandBox(command: command)
            }
            if instruction.addsRepo {
                RepoField()
            }
        }
        .frame(maxWidth: centered ? 460 : .infinity, alignment: centered ? .center : .leading)
        .padding(style == .banner ? 12 : 0)
        .background {
            if style == .banner {
                RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.08))
                RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.3))
            }
        }
    }
}

/// A command to paste into Terminal, with a Copy button.
struct CommandBox: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(command)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy")
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

/// When a source last synced, or why its last sync failed.
struct SyncStatusLabel: View {
    let source: SyncSource
    var alignment = HorizontalAlignment.leading
    @Environment(SyncCoordinator.self) private var sync

    var body: some View {
        if let entry = sync.history.sources[source] {
            if entry.isFailing, let failure = entry.lastFailure {
                VStack(alignment: alignment, spacing: 2) {
                    Label {
                        Text("\(source.displayName) sync failed \(failure, format: .relative(presentation: .named))")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.red)
                    if let error = entry.lastError {
                        Text(Self.explain(error, source: source))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                            .lineLimit(3)
                            .textSelection(.enabled)
                            .help(error)
                    }
                }
                .font(.caption)
            } else if let success = entry.lastSuccess {
                Text("\(source.displayName) synced \(success, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// The errors a new user hits, said in words, with the raw error after.
    static func explain(_ error: String, source: SyncSource) -> String {
        if source == .calendar, error.contains("accessNotConfigured") {
            return "The Google Calendar API isn't enabled in your company's Google Cloud project. Tell whoever runs it. (\(error))"
        }
        return error
    }
}

extension SyncSource {
    var displayName: String {
        switch self {
        case .github: "GitHub"
        case .calendar: "Calendar"
        case .backup: "Backup"
        }
    }
}
