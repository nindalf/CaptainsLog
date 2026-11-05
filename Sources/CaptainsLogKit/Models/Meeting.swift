import Foundation
import SwiftData

@Model
public final class Meeting {
    public var id: UUID = UUID()
    public var calendarEvent: CalendarEvent?
    public var date: Date
    public var title: String
    public var attendees: [Person] = []
    public var isPrivate: Bool = false
    public var project: Project?
    public var prepNotes: String?
    public var notes: String?
    public var transcript: String?
    public var summary: String?
    public var externalURL: URL?
    /// Where the notes were shared with the other attendees.
    public var slackURL: URL?
    // Read through a filtered @Query in views: inserts from the todo side don't notify observers.
    @Relationship(deleteRule: .nullify, inverse: \Todo.meeting)
    public var todos: [Todo]?
    @Relationship(deleteRule: .nullify, inverse: \Todo.completedInMeeting)
    public var completedTodos: [Todo]?

    /// True when nothing has been written beyond what the calendar sync auto-fills, so the
    /// meeting can be discarded if its calendar event is cancelled.
    public var isEmpty: Bool {
        [prepNotes, notes, transcript, summary].allSatisfy { $0?.isEmpty ?? true }
            && project == nil
            && externalURL == nil
            && slackURL == nil
            && (todos ?? []).isEmpty
            && (completedTodos ?? []).isEmpty
    }

    #Index<Meeting>([\.date])

    public init(
        date: Date,
        title: String,
        isPrivate: Bool = false
    ) {
        self.date = date
        self.title = title
        self.isPrivate = isPrivate
    }
}
