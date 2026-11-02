import Foundation
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "backup")

public enum BackupError: Error, LocalizedError {
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}

/// Encrypted snapshots of the store in Google Drive, made by the app on a schedule and by `captains-log backup`,
/// and brought back by `captains-log restore`, under a key made by Settings → Backups or `captains-log backup-setup`.
public enum Backup {
    /// How far setup has got, in the order the steps happen.
    public enum Stage: Int, Comparable, Sendable {
        case needsDrive, needsAge, needsKey, ready

        public static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct File: Equatable, Sendable {
        public let url: URL
        public let date: Date
        public let size: Int64
    }

    public struct Status: Equatable, Sendable {
        public let stage: Stage
        /// Newest first.
        public let backups: [File]
    }

    public struct Created: Sendable {
        public let file: File
        /// Names of the old backups deleted to keep the newest `keep`.
        public let pruned: [String]
    }

    /// `~/Google Drive`. A scratch store gets an empty stand-in beside it, so a sandbox never touches the real Drive.
    public static var driveDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["CAPTAINSLOG_DRIVE_DIR"] { return URL(filePath: dir) }
        if Store.isScratch { return Store.directory.appending(path: "Google Drive") }
        return URL.homeDirectory.appending(path: "Google Drive")
    }

    public static var directory: URL {
        if let dir = ProcessInfo.processInfo.environment["CAPTAINSLOG_BACKUP_DIR"] { return URL(filePath: dir) }
        return driveDirectory.appending(path: "My Drive/CaptainsLog backups")
    }

    private static var driveMissing: Bool {
        ProcessInfo.processInfo.environment["CAPTAINSLOG_BACKUP_DIR"] == nil
            && !FileManager.default.fileExists(atPath: driveDirectory.path(percentEncoded: false))
    }

    private static var noDrive: BackupError {
        .failed("No Google Drive at \(path(driveDirectory)). Install Google Drive for desktop and sign in with your work account (SSO).")
    }

    public static func status() -> Status {
        let stage: Stage
        if driveMissing {
            stage = .needsDrive
        } else if findExecutable("age") == nil || findExecutable("age-keygen") == nil {
            stage = .needsAge
        } else if !exists(directory.appending(path: "identity.age")) || !exists(directory.appending(path: "recipient.txt")) {
            stage = .needsKey
        } else {
            stage = .ready
        }
        return Status(stage: stage, backups: stage == .ready ? backups() : [])
    }

    /// Newest first. Dates come from the names `create` writes, in local time.
    public static func backups(in directory: URL = directory) -> [File] {
        let formatter = stampFormatter()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.compactMap { url -> File? in
            let name = url.lastPathComponent
            guard name.hasPrefix("CaptainsLog-"), name.hasSuffix(".tar.xz.age"),
                let date = formatter.date(from: String(name.dropFirst(12).prefix(17)))
            else { return nil }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return File(url: url, date: date, size: Int64(size))
        }
        .sorted { $0.date > $1.date }
    }

    /// Due when the last success is `interval` old, so sleep, a closed lid or a restart only delays it.
    public static func isDue(_ entry: SyncHistory.Entry?, interval: TimeInterval, now: Date = .now) -> Bool {
        guard let lastSuccess = entry?.lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= interval
    }

    // MARK: - Backing up

    /// Backs up the store into Google Drive, then deletes all but the newest `keep`.
    public static func run(keep: Int) async throws -> Created {
        try await checkDrive()
        return try await create(storeDirectory: Store.directory, backupDirectory: directory, keep: keep)
    }

    /// Throws why the backup folder can't be used. When Drive quits, its folder can vanish, or stay visible while
    /// opening a file in it fails with "Operation not permitted", which reads like a missing permission.
    private static func checkDrive() async throws {
        let recipient = directory.appending(path: "recipient.txt")
        let unreadable = exists(recipient) && (try? Data(contentsOf: recipient)) == nil
        guard driveMissing || unreadable else { return }
        if usesRealDrive, await !isDriveRunning() {
            throw BackupError.failed(
                "Google Drive isn't running. Open Google Drive for desktop, check you're signed in, and try again.")
        }
        if driveMissing { throw noDrive }
        throw BackupError.failed(
            "Can't read \(path(recipient)). Check Google Drive is signed in, and that this app can read it in System Settings → Privacy & Security → Files & Folders.")
    }

    /// Whether backups go to the real Google Drive, not a sandbox's stand-in or a folder set in the environment.
    private static var usesRealDrive: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["CAPTAINSLOG_DRIVE_DIR"] == nil && env["CAPTAINSLOG_BACKUP_DIR"] == nil && !Store.isScratch
    }

    private static func isDriveRunning() async -> Bool {
        (try? await runProcess("/usr/bin/pgrep", arguments: ["-x", "Google Drive"])) != nil
    }

    /// Encrypts a consistent snapshot of the store and `sync-history.json` to the backup key's recipient, then prunes.
    public static func create(
        storeDirectory: URL, backupDirectory: URL, keep: Int, now: Date = .now
    ) async throws -> Created {
        guard keep > 0 else { throw BackupError.failed("Keep at least one backup, not \(keep)") }
        let recipient = backupDirectory.appending(path: "recipient.txt")
        // Never encrypt to a key nobody can decrypt with.
        guard exists(backupDirectory.appending(path: "identity.age")), exists(recipient) else {
            throw BackupError.failed(
                "No backup key in \(backupDirectory.path(percentEncoded: false)). Set up backups in Captain's Log's Settings → Backups.")
        }
        let age = try ageExecutable()
        let store = storeDirectory.appending(path: "CaptainsLog.store")
        guard exists(store) else {
            throw BackupError.failed("No store at \(storeDirectory.path(percentEncoded: false))")
        }

        let fm = FileManager.default
        let tmp = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: tmp) }
        let folder = tmp.appending(path: "CaptainsLog")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)

        let snapshot = folder.appending(path: "CaptainsLog.store")
        try SQLiteFile.snapshot(store, to: snapshot)
        let check = try SQLiteFile.integrityCheck(snapshot)
        guard check == "ok" else { throw BackupError.failed("Snapshot failed integrity_check: \(check)") }
        let history = storeDirectory.appending(path: "sync-history.json")
        if exists(history) { try fm.copyItem(at: history, to: folder.appending(path: "sync-history.json")) }

        let archive = tmp.appending(path: "CaptainsLog.tar.xz")
        try await run("/usr/bin/tar", ["-cJf", path(archive), "-C", path(tmp), "CaptainsLog"], timeout: .seconds(300))

        // Written under .partial and renamed, so Drive never uploads half a backup.
        let name = "CaptainsLog-\(stampFormatter().string(from: now)).tar.xz.age"
        let final = backupDirectory.appending(path: name)
        let partial = backupDirectory.appending(path: name + ".partial")
        try await run(age, ["-R", path(recipient), "-o", path(partial), path(archive)], timeout: .seconds(300))
        try fm.moveItem(at: partial, to: final)
        let size = (try? final.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        logger.info("Backed up to \(name)")

        let pruned = prune(backupDirectory, keep: keep, now: now)
        return Created(file: File(url: final, date: now, size: Int64(size)), pruned: pruned)
    }

    /// Deletes all but the newest `keep` backups, and `.partial` files a day old. Returns the deleted backups' names.
    public static func prune(_ directory: URL, keep: Int, now: Date = .now) -> [String] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in urls where url.lastPathComponent.hasPrefix("CaptainsLog-") && url.pathExtension == "partial" {
            if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                now.timeIntervalSince(modified) > 86400
            {
                try? fm.removeItem(at: url)
            }
        }
        // By the date in the name, so Drive touching mtimes doesn't matter.
        var pruned: [String] = []
        for file in backups(in: directory).dropFirst(keep) {
            do {
                try fm.removeItem(at: file.url)
                pruned.append(file.url.lastPathComponent)
            } catch {
                logger.error("Couldn't prune \(file.url.lastPathComponent): \(error)")
            }
        }
        return pruned
    }

    // MARK: - Restoring

    /// Throws why a restore can't start, if it can't.
    public static func checkCanRestore() throws {
        if driveMissing { throw noDrive }
        guard exists(directory.appending(path: "identity.age")) else {
            throw BackupError.failed(
                "No backup key in \(directory.path(percentEncoded: false)), so there's nothing to restore from.")
        }
        _ = try ageExecutable()
    }

    /// Replaces the store with `backup`. Decrypts, unpacks and checks it in a temporary folder first; age asks for
    /// the passphrase on the terminal. Then `confirm` is told where the current data folder will move, if there is
    /// one, and nothing changes unless it returns true. Returns where the previous data went.
    public static func restore(
        _ backup: File, storeDirectory: URL = Store.directory, backupDirectory: URL = directory, now: Date = .now,
        confirm: (_ aside: URL?) -> Bool
    ) async throws -> URL? {
        let age = try ageExecutable()
        let fm = FileManager.default
        let tmp = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: tmp) }

        // The private key is decrypted inside age, so it never touches the disk. Drive may download the backup first.
        let archive = tmp.appending(path: "backup.tar.xz")
        let identity = backupDirectory.appending(path: "identity.age")
        do {
            try await runInteractiveProcess(age, arguments: ["-d", "-i", path(identity), "-o", path(archive), path(backup.url)])
        } catch ProcessError.nonZeroExit {
            throw BackupError.failed("Couldn't decrypt the backup, so nothing changed.")
        }
        let unpacked = tmp.appending(path: "unpacked")
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: false)
        try await run("/usr/bin/tar", ["-xJf", path(archive), "-C", path(unpacked)], timeout: .seconds(300))

        let restored = unpacked.appending(path: "CaptainsLog")
        let store = restored.appending(path: "CaptainsLog.store")
        guard exists(store) else { throw BackupError.failed("The backup has no CaptainsLog.store; nothing changed.") }
        let check = try SQLiteFile.integrityCheck(store)
        guard check == "ok" else { throw BackupError.failed("The backup failed integrity_check, so nothing changed: \(check)") }

        let hadStore = exists(storeDirectory)
        let aside = storeDirectory.deletingLastPathComponent().appending(
            path: "\(storeDirectory.lastPathComponent)-before-restore-\(stampFormatter().string(from: now))")
        guard confirm(hadStore ? aside : nil) else { throw BackupError.failed("Cancelled; nothing changed.") }

        if hadStore { try fm.moveItem(at: storeDirectory, to: aside) }
        do {
            try fm.createDirectory(at: storeDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: restored, to: storeDirectory)
        } catch {
            if hadStore { try? fm.moveItem(at: aside, to: storeDirectory) }
            throw error
        }
        logger.info("Restored \(backup.url.lastPathComponent)")
        return hadStore ? aside : nil
    }

    // MARK: - Key

    public static let minimumPassphraseLength = 8

    /// Creates the key backups encrypt to: `identity.age`, the private key encrypted with `passphrase`, and
    /// `recipient.txt`, its public key. Refuses if a key exists, since replacing it would make every existing
    /// backup unreadable.
    public static func createKey(passphrase: String) async throws {
        if driveMissing { throw noDrive }
        try await createKey(passphrase: passphrase, in: directory)
    }

    public static func createKey(passphrase: String, in backupDirectory: URL) async throws {
        guard passphrase.count >= minimumPassphraseLength else {
            throw BackupError.failed("The passphrase needs at least \(minimumPassphraseLength) characters.")
        }
        // age reads a passphrase line by line, so a newline would end it early.
        guard !passphrase.contains(where: \.isNewline) else {
            throw BackupError.failed("The passphrase can't contain a line break.")
        }
        let identityFile = backupDirectory.appending(path: "identity.age")
        guard !exists(identityFile) else {
            throw BackupError.failed("\(path(identityFile)) already exists. Backups are set up; not replacing the key.")
        }
        guard let age = findExecutable("age"), let keygen = findExecutable("age-keygen") else {
            throw BackupError.failed("age not found. Run: brew install age")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        // The private key only ever exists unencrypted in memory, and in a fifo nobody else can open.
        let identity = try await runProcess(keygen, arguments: []).stdout
        let recipient = try await runProcess(keygen, arguments: ["-y"], stdinData: identity).stdout
        let recipientLine = String(decoding: recipient, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        let tmp = try makeTemporaryDirectory()
        defer { try? fm.removeItem(at: tmp) }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path(tmp))
        let fifo = tmp.appending(path: "identity")
        guard mkfifo(path(fifo), 0o600) == 0 else {
            throw BackupError.failed("Couldn't create a fifo: \(String(cString: strerror(errno)))")
        }
        do {
            try await encrypt(identity, through: fifo, to: identityFile, passphrase: passphrase, age: age)
        } catch {
            try? fm.removeItem(at: identityFile)
            throw error
        }

        // Decrypt it straight back, so a key that doesn't open with this passphrase is never left in place.
        let check = try? await runProcess(
            "/usr/bin/script",
            arguments: ["-q", "/dev/null", "/bin/sh", "-c", "\"$0\" -d \"$1\" | \"$2\" -y", age, path(identityFile), keygen],
            stdinData: Data((passphrase + "\n").utf8))
        let decrypted = check.map { String(decoding: $0.stdout, as: UTF8.self) } ?? ""
        guard decrypted.firstMatch(of: /age1[0-9a-z]+/).map({ String($0.output) }) == recipientLine else {
            try? fm.removeItem(at: identityFile)
            throw BackupError.failed("The new key didn't decrypt with the passphrase. Nothing was saved; try again.")
        }

        try recipient.write(to: backupDirectory.appending(path: "recipient.txt"))
        for file in [identityFile, backupDirectory.appending(path: "recipient.txt")] {
            try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: path(file))
        }
        logger.info("Created the backup key")
    }

    /// `age -p` reads the passphrase only from a terminal, so script(1) gives it one, and its stdin with it. The
    /// key goes in through `fifo` instead.
    private static func encrypt(
        _ identity: Data, through fifo: URL, to output: URL, passphrase: String, age: String
    ) async throws {
        let fifoPath = path(fifo)
        // Opening a fifo to write blocks until something opens it to read: age, or the unblocking below.
        let writer = Task.detached(priority: .utility) {
            let fd = open(fifoPath, O_WRONLY)
            guard fd >= 0 else { return }
            // A reader gone mid-write gives EPIPE, not a SIGPIPE that would kill the app.
            _ = fcntl(fd, F_SETNOSIGPIPE, 1)
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try? handle.write(contentsOf: identity)
        }
        var failed = false
        do {
            _ = try await runProcess(
                "/usr/bin/script", arguments: ["-q", "/dev/null", age, "-p", "-o", path(output), fifoPath],
                stdinData: Data("\(passphrase)\n\(passphrase)\n".utf8), timeout: .seconds(60))
        } catch {
            failed = true
        }
        // If age never opened the fifo, the writer is still waiting. Hold a reader open until it has finished.
        let unblock = open(fifoPath, O_RDONLY | O_NONBLOCK)
        await writer.value
        if unblock >= 0 { close(unblock) }
        if failed { throw BackupError.failed("age failed to encrypt the key.") }
    }

    // MARK: - Helpers

    private static func stampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        return formatter
    }

    private static func ageExecutable() throws -> String {
        guard let age = findExecutable("age") else { throw BackupError.failed("age not found. Run: brew install age") }
        return age
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "CaptainsLog-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func run(_ executable: String, _ arguments: [String], timeout: Duration) async throws {
        do {
            _ = try await runProcess(executable, arguments: arguments, timeout: timeout)
        } catch ProcessError.nonZeroExit(_, let stderr) {
            let name = URL(filePath: executable).lastPathComponent
            throw BackupError.failed("\(name) failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: path(url))
    }

    private static func path(_ url: URL) -> String { url.path(percentEncoded: false) }
}
