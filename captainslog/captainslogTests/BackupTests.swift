import Foundation
import SQLite3
import Testing
import CaptainsLogKit

/// Backs up and restores between temp folders, with an unencrypted key so age never asks for a passphrase.
@Suite(.enabled(if: findExecutable("age") != nil && findExecutable("age-keygen") != nil))
struct BackupTests {
    private let root: URL
    private let store: URL
    private let backups: URL

    init() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "BackupTests-\(UUID().uuidString)")
        store = root.appending(path: "CaptainsLog")
        backups = root.appending(path: "backups")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        _ = try await runProcess(findExecutable("age-keygen")!, arguments: ["-o", path(backups.appending(path: "identity.age"))])
        let recipient = try await runProcess(findExecutable("age-keygen")!, arguments: ["-y", path(backups.appending(path: "identity.age"))])
        try recipient.stdout.write(to: backups.appending(path: "recipient.txt"))
    }

    @Test func aBackupTakenMidWriteRestoresWhatWasCommitted() async throws {
        // An open connection with the row still in the WAL, as while the app is running.
        let db = try open(store.appending(path: "CaptainsLog.store"))
        defer { sqlite3_close(db) }
        try exec(db, "PRAGMA journal_mode=WAL; CREATE TABLE t(x); INSERT INTO t VALUES (42);")
        try #require(FileManager.default.fileExists(atPath: path(store.appending(path: "CaptainsLog.store-wal"))))
        try Data("{}".utf8).write(to: store.appending(path: "sync-history.json"))

        let created = try await Backup.create(storeDirectory: store, backupDirectory: backups, keep: 5)
        #expect(Backup.backups(in: backups).map(\.url.lastPathComponent) == [created.file.url.lastPathComponent])
        try exec(db, "INSERT INTO t VALUES (99);")

        var offered: URL?
        let aside = try await Backup.restore(created.file, storeDirectory: store, backupDirectory: backups) {
            offered = $0
            return true
        }
        #expect(aside != nil && aside == offered)
        #expect(try values(in: store.appending(path: "CaptainsLog.store")) == [42])
        #expect(FileManager.default.fileExists(atPath: path(store.appending(path: "sync-history.json"))))
        #expect(try values(in: aside!.appending(path: "CaptainsLog.store")) == [42, 99])
        try? FileManager.default.removeItem(at: root)
    }

    @Test func declinedRestoreChangesNothing() async throws {
        _ = try await runProcess("/usr/bin/sqlite3", arguments: [path(store.appending(path: "CaptainsLog.store")), "CREATE TABLE t(x); INSERT INTO t VALUES (1);"])
        let created = try await Backup.create(storeDirectory: store, backupDirectory: backups, keep: 5)
        await #expect(throws: BackupError.self) {
            _ = try await Backup.restore(created.file, storeDirectory: store, backupDirectory: backups) { _ in false }
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: path(root)).sorted()
        #expect(left == ["CaptainsLog", "backups"])
        try? FileManager.default.removeItem(at: root)
    }

    @Test func pruneKeepsTheNewestByNameAndClearsStalePartials() throws {
        let names = ["CaptainsLog-2026-10-01T090000.tar.xz.age", "CaptainsLog-2026-10-03T090000.tar.xz.age",
                     "CaptainsLog-2026-10-02T090000.tar.xz.age", "CaptainsLog-2026-10-04T090000.tar.xz.age.partial",
                     "notes.txt"]
        for name in names { try Data().write(to: backups.appending(path: name)) }
        let now = Date.now.addingTimeInterval(2 * 86400)

        #expect(Backup.prune(backups, keep: 2, now: now) == ["CaptainsLog-2026-10-01T090000.tar.xz.age"])
        let left = try FileManager.default.contentsOfDirectory(atPath: path(backups)).sorted()
        #expect(left == ["CaptainsLog-2026-10-02T090000.tar.xz.age", "CaptainsLog-2026-10-03T090000.tar.xz.age",
                         "identity.age", "notes.txt", "recipient.txt"])
        try? FileManager.default.removeItem(at: root)
    }

    @Test func aNewKeyDecryptsBackupsWithItsPassphraseAndIsNeverReplaced() async throws {
        let keyed = root.appending(path: "keyed")
        let passphrase = "correct horse battery"
        try await Backup.createKey(passphrase: passphrase, in: keyed)
        for name in ["identity.age", "recipient.txt"] {
            let attributes = try FileManager.default.attributesOfItem(atPath: path(keyed.appending(path: name)))
            #expect(attributes[.posixPermissions] as? Int == 0o444)
        }
        let identity = try Data(contentsOf: keyed.appending(path: "identity.age"))
        #expect(String(decoding: identity, as: UTF8.self).hasPrefix("age-encryption.org/v1"))

        _ = try await runProcess("/usr/bin/sqlite3", arguments: [path(store.appending(path: "CaptainsLog.store")), "CREATE TABLE t(x); INSERT INTO t VALUES (7);"])
        let created = try await Backup.create(storeDirectory: store, backupDirectory: keyed, keep: 5)
        // What a restore does, with script(1) standing in for the person typing the passphrase.
        let archive = root.appending(path: "decrypted.tar.xz")
        _ = try await runProcess(
            "/usr/bin/script",
            arguments: ["-q", "/dev/null", findExecutable("age")!, "-d", "-i", path(keyed.appending(path: "identity.age")),
                        "-o", path(archive), path(created.file.url)],
            stdinData: Data((passphrase + "\n").utf8))
        let unpacked = root.appending(path: "unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        _ = try await runProcess("/usr/bin/tar", arguments: ["-xJf", path(archive), "-C", path(unpacked)])
        #expect(try values(in: unpacked.appending(path: "CaptainsLog/CaptainsLog.store")) == [7])

        await #expect(throws: BackupError.self) { try await Backup.createKey(passphrase: "another passphrase", in: keyed) }
        #expect(try Data(contentsOf: keyed.appending(path: "identity.age")) == identity)
        try? FileManager.default.removeItem(at: root)
    }

    @Test func aShortPassphraseMakesNoKey() async throws {
        let keyed = root.appending(path: "keyed")
        await #expect(throws: BackupError.self) { try await Backup.createKey(passphrase: "short", in: keyed) }
        #expect(!FileManager.default.fileExists(atPath: path(keyed.appending(path: "identity.age"))))
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - SQLite

    private func open(_ url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open(path(url), &db) == SQLITE_OK, let db else { throw BackupError.failed("open") }
        return db
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw BackupError.failed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func values(in url: URL) throws -> [Int] {
        let db = try open(url)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT x FROM t ORDER BY x", -1, &statement, nil) == SQLITE_OK else {
            throw BackupError.failed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        var result: [Int] = []
        while sqlite3_step(statement) == SQLITE_ROW { result.append(Int(sqlite3_column_int64(statement, 0))) }
        return result
    }

    private func path(_ url: URL) -> String { url.path(percentEncoded: false) }
}
