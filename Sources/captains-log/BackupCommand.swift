import ArgumentParser
import CaptainsLogKit
import Foundation

struct BackupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backup",
        abstract: "Encrypt a snapshot of the store into Google Drive, as the app does on schedule",
        discussion: "Safe while the app is running. Keeps the newest backups, as many as Settings → Backups says. Needs backups set up in Settings → Backups first. Records in `status` like the app's backups."
    )

    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false

    mutating func run() async throws {
        let created: Backup.Created
        do {
            created = try await Backup.run(keep: AppSettings().backupKeep)
            SyncHistory.update { $0.recordSuccess(.backup) }
        } catch {
            SyncHistory.update { $0.recordFailure(.backup, error: error.localizedDescription) }
            throw ValidationError(error.localizedDescription)
        }
        try printJSON(
            BackupDTO(
                file: created.file.url.path(percentEncoded: false), date: created.file.date, size: created.file.size,
                pruned: created.pruned),
            pretty: pretty)
    }

    struct BackupDTO: Encodable {
        let file: String
        let date: Date
        let size: Int64
        let pruned: [String]
    }
}

struct BackupSetup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backup-setup",
        abstract: "Create the backup key in Google Drive, protected by a passphrase. Interactive: run it in a terminal",
        discussion: "Once per person, like Set Up Backups in Settings → Backups. Refuses if the key exists, since a new one would make every existing backup unreadable."
    )

    mutating func run() async throws {
        guard isatty(STDIN_FILENO) == 1 else {
            throw ValidationError("Setup is interactive; run captains-log backup-setup in a terminal.")
        }
        say("Backups are encrypted with a key that is itself protected by a passphrase.")
        say("If you forget the passphrase, every backup is unreadable. Nobody can recover it.")
        say("")
        var passphrase = ""
        while passphrase.isEmpty {
            guard let first = askSecret("Passphrase (at least \(Backup.minimumPassphraseLength) characters): "),
                let second = askSecret("Again: ")
            else { throw ExitCode.failure }
            if first.count < Backup.minimumPassphraseLength {
                say("Too short.")
            } else if first != second {
                say("They don't match.")
            } else {
                passphrase = first
            }
        }
        do {
            try await Backup.createKey(passphrase: passphrase)
        } catch {
            throw ValidationError(error.localizedDescription)
        }
        say("Backup key created in \(Backup.directory.path(percentEncoded: false))")
        say("Run: captains-log backup")
    }
}

struct Restore: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Replace the store with a backup from Google Drive. Interactive: run it in a terminal",
        discussion: "Asks you to quit the app, lists the backups newest first, and asks which to restore and for the backup passphrase. It checks the backup before changing anything, and moves your current data folder aside rather than deleting it."
    )

    mutating func run() async throws {
        guard isatty(STDIN_FILENO) == 1 else {
            throw ValidationError("Restore is interactive; run captains-log restore in a terminal.")
        }
        do {
            try Backup.checkCanRestore()
        } catch {
            throw ValidationError(error.localizedDescription)
        }

        // The app holds the store open; replacing it underneath would corrupt it. Scratch stores belong to sandboxes.
        if !Store.isScratch {
            while await appIsRunning() {
                guard ask("Quit Captain's Log (every copy), then press Return. ") != nil else { throw ExitCode.failure }
            }
        }

        let backups = Backup.backups()
        guard !backups.isEmpty else {
            throw ValidationError("No backups in \(Backup.directory.path(percentEncoded: false))")
        }
        say("Backups in \(Backup.directory.path(percentEncoded: false)), newest first:")
        for (index, backup) in backups.enumerated() {
            say(String(format: "%3d) ", index + 1) + "\(label(backup))  (\(backup.size.formatted(.byteCount(style: .file))))")
        }
        var chosen: Backup.File?
        while chosen == nil {
            guard let answer = ask("Restore which? ") else { throw ExitCode.failure }
            if let number = Int(answer.trimmingCharacters(in: .whitespaces)), backups.indices.contains(number - 1) {
                chosen = backups[number - 1]
            } else {
                say("Pick a number from the list.")
            }
        }
        let backup = chosen!

        say("Decrypting \(backup.url.lastPathComponent). Older backups may download from Drive first.")
        let aside: URL?
        do {
            aside = try await Backup.restore(backup) { aside in
                say("")
                say("This replaces your data with the backup from \(label(backup)).")
                if let aside { say("Your current data folder moves to: \(aside.path(percentEncoded: false))") }
                let answer = ask("Restore? [y/N] ")?.lowercased()
                return answer == "y" || answer == "yes"
            }
        } catch {
            throw ValidationError(error.localizedDescription)
        }

        say("Restored. Open Captain's Log; it syncs GitHub and the calendar again on launch.")
        if let aside {
            say("Your previous data is in \(aside.path(percentEncoded: false)). Delete it once you're happy with the restore.")
        }
    }

    private func label(_ backup: Backup.File) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: backup.date)
    }

    private func appIsRunning() async -> Bool {
        // pgrep exits 1 when nothing matches.
        (try? await runProcess("/usr/bin/pgrep", arguments: ["-x", "Captain's Log"])) != nil
    }
}

/// Restore and setup talk to a person, so its messages and prompts go to stderr, unbuffered.
private func say(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

/// The answer, or nil at end of input.
private func ask(_ prompt: String) -> String? {
    FileHandle.standardError.write(Data(prompt.utf8))
    return readLine()
}

/// Read from the terminal with echo off, or nil at end of input.
private func askSecret(_ prompt: String) -> String? {
    var buffer = [CChar](repeating: 0, count: 1024)
    defer { buffer.withUnsafeMutableBufferPointer { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
    guard let line = readpassphrase(prompt, &buffer, buffer.count, Int32(RPP_REQUIRE_TTY)) else { return nil }
    return String(cString: line)
}
