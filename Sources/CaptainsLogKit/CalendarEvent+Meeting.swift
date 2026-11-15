import Foundation
import SwiftData

extension CalendarEvent {
    /// A meeting worth prepping: timed, not an interview, and with at least one other attendee.
    public var isMeeting: Bool {
        !isAllDay && interview == nil && attendees.count >= 2
    }

    /// Makes and inserts a meeting for this event, as the event popover's Add Notes does:
    /// the event's title, start and attendees, and the project of the rest of its series if they
    /// all share one. Meeting notes default to internal.
    @discardableResult
    public func createMeeting(in context: ModelContext) -> Meeting {
        let project = seriesID.flatMap { series in
            (try? context.fetch(FetchDescriptor<Meeting>())).flatMap { Meeting.sharedProject(of: Meeting.inSeries(series, among: $0)) }
        }
        let meeting = Meeting(date: startTime, title: title)
        meeting.attendees = attendees
        meeting.calendarEvent = self
        meeting.project = project
        context.insert(meeting)
        return meeting
    }
}
