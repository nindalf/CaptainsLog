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
    public var externalID: String
    /// Hidden by the user. Kept as a row rather than removed so sync can tell it apart from a
    /// new event and doesn't bring it back.
    public var isHidden: Bool = false
    /// Mine to delete rather than decline. Set by sync, so false until an event's first sync after V3.
    public var isOrganizedByMe: Bool = false
    /// An invitation organised outside my email domain, so anyone could have written its title.
    /// From schema V6, set by sync: false until an event's first sync after it.
    public var isFromOutside: Bool = false
    /// I accepted it. Set by sync from schema V6.
    public var isAcceptedByMe: Bool = false

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
