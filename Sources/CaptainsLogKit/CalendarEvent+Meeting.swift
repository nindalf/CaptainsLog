import Foundation
import SwiftData

extension CalendarEvent {
    /// A meeting worth prepping: timed, not an interview, and with at least one other attendee.
    public var isMeeting: Bool {
        !isAllDay && interview == nil && attendees.count >= 2
    }

    /// Makes and inserts a meeting for this event, as the event popover's Add Notes does:
    /// the event's title, start and attendees. Meeting notes default to internal.
    @discardableResult
    public func createMeeting(in context: ModelContext) -> Meeting {
        let meeting = Meeting(date: startTime, title: title)
        meeting.attendees = attendees
        meeting.calendarEvent = self
        context.insert(meeting)
        return meeting
    }
}
