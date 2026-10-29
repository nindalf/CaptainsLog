import Foundation
import SwiftData

/// Deletes SwiftData's persistent history, which records every save and can't be switched off.
/// Nothing reads it, but SwiftData may use recent transactions to merge the CLI's writes into the
/// running app, so a window is kept. Only the app prunes: the CLI can't know what the app has seen.
@ModelActor
public actor HistoryPruner {
    public static let retention: TimeInterval = 14 * 24 * 60 * 60

    /// Returns whether anything was old enough to delete.
    @discardableResult
    public func prune(before cutoff: Date = .now.addingTimeInterval(-retention)) throws -> Bool {
        var newestOld = HistoryDescriptor<DefaultHistoryTransaction>(
            predicate: #Predicate { $0.timestamp < cutoff },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        newestOld.fetchLimit = 1
        guard let newest = try modelContext.fetchHistory(newestOld).first?.token else { return false }
        try modelContext.deleteHistory(
            HistoryDescriptor<DefaultHistoryTransaction>(predicate: #Predicate { $0.token <= newest })
        )
        return true
    }
}
