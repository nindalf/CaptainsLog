import SwiftUI
import SwiftData
import CaptainsLogKit

/// Declining or deleting an event in Google Calendar. Either way the event is gone from the calendar,
/// as the next sync would find, so callers then drop it here with `deleteWithEmptyStubs`.
enum CalendarEventRemoval {
    enum Action { case decline, delete }

    /// Delete for an event I organise, Decline for one I'm invited to. Timed events only: all-day
    /// ones can come from calendars other than the primary. `CalendarWrite` checks with Google too,
    /// for events last synced before sync recorded who organised them.
    static func offered(for event: CalendarEvent) -> Action? {
        guard CalendarWrite.isAvailable, !event.isAllDay else { return nil }
        return event.isOrganizedByMe ? .delete : .decline
    }

    @MainActor
    static func write(_ action: Action, to event: CalendarEvent) async throws {
        let id = event.externalID
        switch action {
        case .decline: try await CalendarWrite.decline(eventID: id)
        case .delete: try await CalendarWrite.delete(eventID: id)
        }
    }

    static func deletePrompt(_ event: CalendarEvent) -> String {
        "Delete \u{201C}\(event.title)\u{201D} from Google Calendar?"
    }

    static let deleteMessage = "Guests are told it's cancelled."
}
