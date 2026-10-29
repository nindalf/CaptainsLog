import Foundation

public enum BackupError: Error, LocalizedError {
    case scriptMissing(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .scriptMissing(let name): "\(name).sh is missing from the app bundle"
        case .failed(let message): message
        }
    }
}

/// Runs `backup.sh` and `backup-setup.sh`, which ship as resources so the app runs exactly the scripts the
/// `just` recipes do.
public enum Backup {
    /// How far setup has got, in the order the steps happen.
    public enum Stage: Int, Comparable, Sendable {
        case needsDrive, needsAge, needsKey, ready

        public static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct File: Equatable, Sendable {
        public let date: Date
        public let size: Int64
    }

    public struct Status: Equatable, Sendable {
        public let stage: Stage
        /// Newest first.
        public let backups: [File]
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

    /// Checks the same things, in the same order, as the scripts do before they start.
    public static func status() -> Status {
        let fm = FileManager.default
        let stage: Stage
        if ProcessInfo.processInfo.environment["CAPTAINSLOG_BACKUP_DIR"] == nil,
            !fm.fileExists(atPath: driveDirectory.path(percentEncoded: false))
        {
            stage = .needsDrive
        } else if findExecutable("age") == nil || findExecutable("age-keygen") == nil {
            stage = .needsAge
        } else if !fm.fileExists(atPath: directory.appending(path: "identity.age").path(percentEncoded: false))
            || !fm.fileExists(atPath: directory.appending(path: "recipient.txt").path(percentEncoded: false))
        {
            stage = .needsKey
        } else {
            stage = .ready
        }
        return Status(stage: stage, backups: stage == .ready ? backups() : [])
    }

    /// Dates come from the names `backup.sh` writes, in local time.
    static func backups() -> [File] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.compactMap { url -> File? in
            let name = url.lastPathComponent
            guard name.hasPrefix("CaptainsLog-"), name.hasSuffix(".tar.xz.age"),
                let date = formatter.date(from: String(name.dropFirst(12).prefix(17)))
            else { return nil }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return File(date: date, size: Int64(size))
        }
        .sorted { $0.date > $1.date }
    }

    /// Due when the last success is `interval` old, so sleep, a closed lid or a restart only delays it.
    public static func isDue(_ entry: SyncHistory.Entry?, interval: TimeInterval, now: Date = .now) -> Bool {
        guard let lastSuccess = entry?.lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= interval
    }

    /// Backs up, then deletes all but the newest `keep`.
    public static func run(keep: Int) async throws {
        try await runScript("backup", environment: ["CAPTAINSLOG_BACKUP_KEEP": String(keep)], timeout: .seconds(300))
    }

    /// Creates the key backups encrypt to. The script refuses if one exists, since replacing it would make
    /// every existing backup unreadable.
    public static func createKey(passphrase: String) async throws {
        try await runScript(
            "backup-setup", arguments: ["--passphrase-stdin"], stdin: Data((passphrase + "\n").utf8),
            timeout: .seconds(60))
    }

    private static func runScript(
        _ name: String, arguments: [String] = [], environment: [String: String] = [:], stdin: Data? = nil,
        timeout: Duration
    ) async throws {
        guard let script = Bundle.module.url(forResource: name, withExtension: "sh") else {
            throw BackupError.scriptMissing(name)
        }
        var env = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        env["CAPTAINSLOG_DRIVE_DIR"] = driveDirectory.path(percentEncoded: false)
        do {
            _ = try await runProcess(
                "/bin/bash", arguments: [script.path(percentEncoded: false)] + arguments, environment: env,
                stdinData: stdin, timeout: timeout)
        } catch ProcessError.nonZeroExit(_, let stderr) {
            throw BackupError.failed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
