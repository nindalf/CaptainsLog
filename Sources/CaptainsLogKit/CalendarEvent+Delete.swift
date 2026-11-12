import Foundation
import SwiftData

extension CalendarEvent {
    /// Removes this event along with any auto-created meeting or interview stub hanging off it.
    /// Those relationships nullify rather than cascade, so a meeting or interview the user has
    /// actually written in survives as an orphan with no `calendarEvent`.
    public func deleteWithEmptyStubs(in context: ModelContext) {
        // Sync may have removed it while a decline or delete was waiting on Google.
        guard modelContext != nil, !isDeleted else { return }
        if let meeting, meeting.isEmpty {
            context.delete(meeting)
        }
        if let interview, interview.isEmpty {
            context.delete(interview)
        }
        context.delete(self)
    }
}
