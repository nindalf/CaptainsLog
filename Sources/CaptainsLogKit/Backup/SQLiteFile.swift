import Foundation
import SQLite3

/// Copies and checks store files through SQLite itself, so a copy is consistent even while the app is writing.
enum SQLiteFile {
    /// A consistent copy of `source` at `destination`, as a single file with no WAL beside it. Opens the source read-only.
    static func snapshot(_ source: URL, to destination: URL) throws {
        let src = try open(source, flags: SQLITE_OPEN_READONLY)
        defer { sqlite3_close(src) }
        sqlite3_busy_timeout(src, 10_000)
        let dst = try open(destination, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        defer { sqlite3_close(dst) }
        guard let backup = sqlite3_backup_init(dst, "main", src, "main") else {
            throw BackupError.failed("Snapshot failed: \(String(cString: sqlite3_errmsg(dst)))")
        }
        let rc = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        guard rc == SQLITE_DONE else {
            throw BackupError.failed("Snapshot failed: \(String(cString: sqlite3_errstr(rc)))")
        }
        guard sqlite3_exec(dst, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
            throw BackupError.failed("Snapshot failed: \(String(cString: sqlite3_errmsg(dst)))")
        }
    }

    /// "ok", or the problems SQLite found.
    static func integrityCheck(_ url: URL) throws -> String {
        let db = try open(url, flags: SQLITE_OPEN_READONLY)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK else {
            return String(cString: sqlite3_errmsg(db))
        }
        defer { sqlite3_finalize(statement) }
        var lines: [String] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) {
                lines.append(String(cString: text))
            } else if rc == SQLITE_DONE {
                break
            } else {
                return String(cString: sqlite3_errmsg(db))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func open(_ url: URL, flags: Int32) throws -> OpaquePointer {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(url.path(percentEncoded: false), &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? String(cString: sqlite3_errstr(rc))
            sqlite3_close(db)
            throw BackupError.failed("Can't open \(url.path(percentEncoded: false)): \(message)")
        }
        return db
    }
}
