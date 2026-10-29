import AppKit
import SwiftUI
import CaptainsLogKit

/// Shows where backups are up to: an offer to set them up, the current setup step, or how they're going.
struct BackupSettingsSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var sync

    @State private var status: Backup.Status?
    @State private var lastRun: SyncHistory.Entry?
    @State private var settingUp = false
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var creatingKey = false
    @State private var keyError: String?

    private static let driveDownload = URL(string: "https://www.google.com/drive/download/")!
    private static let minimumPassphrase = 8

    var body: some View {
        Section {
            if let status {
                if status.stage == .ready {
                    ready(status)
                } else if settingUp {
                    steps(status.stage)
                } else {
                    offer
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text("Backups")
                BackupInfoButton()
            }
        }
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .onChange(of: sync.isBackingUp) { refresh() }
    }

    private var offer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Backups aren't set up")
                Text("Your data is only on this Mac. Backups are encrypted and saved to your Google Drive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Set Up Backups") { settingUp = true }
        }
    }

    // MARK: Setup

    @ViewBuilder
    private func steps(_ stage: Backup.Stage) -> some View {
        step(1, "Install Google Drive for desktop", for: .needsDrive, current: stage) {
            Text("Sign in with your work account. It creates the Google Drive folder in your home folder.")
            HStack {
                Link("Download Google Drive", destination: Self.driveDownload)
                Spacer()
                Button("Check Again", action: refresh)
            }
        }
        step(2, "Install age", for: .needsAge, current: stage) {
            Text("age encrypts the backups. Install it with Homebrew:")
            HStack {
                Text("brew install age")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install age", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy")
                Spacer()
                Button("Check Again", action: refresh)
            }
        }
        step(3, "Choose a passphrase", for: .needsKey, current: stage) {
            Text("It protects the key that unlocks your backups. You need it to restore on a new Mac. If you forget it, every backup is unreadable and nobody can recover it.")
            Group {
                SecureField("Passphrase", text: $passphrase, prompt: Text("Passphrase"))
                SecureField("Confirm passphrase", text: $confirmation, prompt: Text("Confirm passphrase"))
                    .onSubmit { if passphraseProblem == nil { createKey() } }
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 320)
            HStack {
                if let problem = passphraseProblem, !passphrase.isEmpty {
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                } else if let keyError {
                    Text(keyError).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                if creatingKey { ProgressView().controlSize(.small) }
                Button("Create Key", action: createKey)
                    .disabled(passphraseProblem != nil || creatingKey)
            }
        }
    }

    private func step<Content: View>(
        _ number: Int, _ title: String, for stage: Backup.Stage, current: Backup.Stage,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: current > stage ? "checkmark.circle.fill" : "\(number).circle")
                    .foregroundStyle(current > stage ? .green : current == stage ? .primary : .secondary)
                Text(title)
                    .foregroundStyle(current < stage ? .secondary : .primary)
            }
            if current == stage {
                content()
                    .padding(.leading, 24)
            }
        }
    }

    private var passphraseProblem: String? {
        if passphrase.count < Self.minimumPassphrase { return "At least \(Self.minimumPassphrase) characters" }
        if passphrase != confirmation { return "The passphrases don't match" }
        return nil
    }

    private func createKey() {
        guard !creatingKey else { return }
        creatingKey = true
        keyError = nil
        let chosen = passphrase
        Task {
            defer { creatingKey = false }
            do {
                try await Backup.createKey(passphrase: chosen)
                passphrase = ""
                confirmation = ""
                refresh()
                await sync.backUp()
            } catch {
                keyError = error.localizedDescription
            }
        }
    }

    // MARK: Ready

    @ViewBuilder
    private func ready(_ status: Backup.Status) -> some View {
        @Bindable var settings = settings
        LabeledContent("Last backup") {
            if sync.isBackingUp {
                Text("Backing up…")
            } else if let newest = status.backups.first {
                Text("\(newest.date, format: .relative(presentation: .named)), \(newest.size.formatted(.byteCount(style: .file)))")
            } else {
                Text("None yet")
            }
        }
        if let lastRun, lastRun.isFailing, let error = lastRun.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
        LabeledContent("Back up every") {
            Picker("", selection: $settings.backupInterval) {
                Text("1 hour").tag(TimeInterval(3600))
                Text("6 hours").tag(TimeInterval(6 * 3600))
                Text("12 hours").tag(TimeInterval(12 * 3600))
                Text("1 day").tag(TimeInterval(24 * 3600))
            }
            .frame(width: 120)
        }
        LabeledContent {
            Picker("", selection: $settings.backupKeep) {
                ForEach([7, 14, 30, 60, 90], id: \.self) { Text("\($0)").tag($0) }
            }
            .frame(width: 120)
        } label: {
            Text("Keep the newest")
            Text("\(status.backups.count) kept now, about \(coverage) of history when full")
        }
        HStack {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([Backup.directory])
            }
            Spacer()
            Button("Back Up Now") { Task { await sync.backUp() } }
                .disabled(sync.isBackingUp)
        }
    }

    private var coverage: String {
        let span = Double(settings.backupKeep) * settings.backupInterval
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = span >= 2 * 86400 ? [.day] : [.hour]
        formatter.unitsStyle = .full
        return formatter.string(from: span) ?? ""
    }

    private func refresh() {
        status = Backup.status()
        lastRun = SyncHistory.load().sources[.backup]
    }
}

/// An (i) button that explains where backups go and who can read them.
private struct BackupInfoButton: View {
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .help("How backups work")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How backups work").font(.headline)
                Text("Backups are saved to your work Google Drive.")
                Text("Each one is encrypted with `age`. The key that unlocks them sits in the same folder, protected by your passphrase.")
                Text("Without the passphrase, nobody can read or restore them: not Google, not your Drive admins, not even you. Don't lose it; it can't be recovered.")
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 300, alignment: .leading)
            .padding()
        }
    }
}
