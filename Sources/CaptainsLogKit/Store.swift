import Foundation
import SwiftData

public enum Store {
    // CAPTAINSLOG_STORE_DIR points the app and CLI at a scratch store (used by scripts/ui.swift).
    // Unit tests run inside the app host, so any process with XCTest loaded gets a temp store too.
    private static let scratchDir: String? = {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["CAPTAINSLOG_STORE_DIR"] { return dir }
        if env["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory.appending(path: "CaptainsLog-tests").path(percentEncoded: false)
        }
        return nil
    }()

    /// Scratch instances skip sync so they never pull real data.
    public static var isScratch: Bool { scratchDir != nil }

    /// The directory holding the store, and files kept beside it such as `SyncHistory`'s.
    public static var directory: URL {
        scratchDir.map { URL(filePath: $0) } ?? URL.applicationSupportDirectory.appending(path: "CaptainsLog")
    }

    public static func makeContainer() throws -> ModelContainer {
        let schema = Schema(CaptainsLogSchemaV1.models)
        let dir = directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "CaptainsLog.store")
        let config = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema,
            migrationPlan: CaptainsLogMigrationPlan.self,
            configurations: [config]
        )
    }
}
