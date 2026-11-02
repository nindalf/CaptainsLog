import Foundation
import SwiftData

extension CalendarEvent {
    /// Removes the events overlapping `window` whose ids aren't in `seen`, the ids a complete fetch of
    /// every synced calendar returned. Google doesn't send a cancelled record for every deletion (an
    /// instance dropped from a recurring series, an interview pulled by the recruiting system), so
    /// absence is the signal. Written meetings and interviews survive (`deleteWithEmptyStubs`).
    /// An empty `seen` removes nothing: no events at all means a bad fetch, not an empty calendar.
    @discardableResult
    public static func removeMissing(from window: DateInterval, keeping seen: Set<String>, in context: ModelContext)
        throws -> Int
    {
        guard !seen.isEmpty else { return 0 }
        let start = window.start
        let end = window.end
        let overlapping = try context.fetch(
            FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.endTime > start && $0.startTime < end })
        )
        let missing = overlapping.filter { !seen.contains($0.externalID) }
        for event in missing {
            event.deleteWithEmptyStubs(in: context)
        }
        return missing.count
    }
}
