import Foundation
import SwiftData

@Model
public final class CalendarEvent {
    public var id: UUID = UUID()
    public var title: String
    public var startTime: Date
    public var endTime: Date
    public var attendees: [Person] = []
    public var location: String?
    public var meetingURL: URL?
    public var isRecurring: Bool = false
    public var isAllDay: Bool = false
    public var participantCount: Int = 0
    public var confirmedCount: Int = 0
    public var externalID: String
    /// Hidden by the user. Kept as a row rather than removed so sync can tell it apart from a
    /// new event and doesn't bring it back.
    public var isHidden: Bool = false

    #Unique<CalendarEvent>([\.externalID])

    @Relationship(deleteRule: .nullify, inverse: \Meeting.calendarEvent)
    public var meeting: Meeting?
    @Relationship(deleteRule: .nullify, inverse: \Interview.calendarEvent)
    public var interview: Interview?

    public init(
        title: String,
        startTime: Date,
        endTime: Date,
        externalID: String
    ) {
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.externalID = externalID
    }
}
