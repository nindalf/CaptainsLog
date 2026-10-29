import Foundation
import SwiftData
import Testing
import CaptainsLogKit

// One shared in-memory container for the whole suite, serialized — see PersonMergeTests for why.
@Suite(.serialized)
@MainActor
struct HistoryPrunerTests {
    private static let container: ModelContainer = {
        let schema = Schema(CaptainsLogSchemaV1.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func save(_ title: String) throws {
        let context = Self.container.mainContext
        context.insert(LogEntry(timestamp: .now, source: .manual, title: title, content: ""))
        try context.save()
    }

    private func history() throws -> [DefaultHistoryTransaction] {
        try Self.container.mainContext.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
    }

    @Test func keepsTransactionsFromAfterTheCutoff() async throws {
        try save("before")
        try await Task.sleep(for: .milliseconds(50))
        let cutoff = Date.now
        try await Task.sleep(for: .milliseconds(50))
        try save("after")

        #expect(try await HistoryPruner(modelContainer: Self.container).prune(before: cutoff))
        let remaining = try history()
        #expect(!remaining.isEmpty)
        #expect(remaining.allSatisfy { $0.timestamp >= cutoff })
    }

    @Test func deletesEverythingBeforeTheCutoff() async throws {
        try save("old")
        try await Task.sleep(for: .milliseconds(50))

        try await HistoryPruner(modelContainer: Self.container).prune(before: .now)

        #expect(try history().isEmpty)
    }

    @Test func doesNothingWhenNoTransactionIsOldEnough() async throws {
        try save("recent")
        let before = try history().count

        #expect(try await !HistoryPruner(modelContainer: Self.container).prune(before: .distantPast))
        #expect(try history().count == before)
    }
}
