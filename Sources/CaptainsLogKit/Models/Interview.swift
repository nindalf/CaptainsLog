import Foundation
import SwiftData

@Model
public final class Interview {
    public var id: UUID = UUID()
    public var date: Date
    public var candidateName: String
    public var role: String?
    public var problemName: String?
    public var whiteboardLink: String?
    public var calendarEvent: CalendarEvent?
    public var isPrivate: Bool = true
    public var rawNotes: String?
    public var upsides: String?
    public var riskFactors: String?
    public var levelAssessment: String?
    public var recommendation: Recommendation?
    public var conclusion: String?
    public var coInterviewer: Person?
    public var debriefDate: Date?
    public var debriefNotes: String?
    // Read through a filtered @Query in views: inserts from the todo side don't notify observers.
    @Relationship(deleteRule: .nullify, inverse: \Todo.interview)
    public var todos: [Todo]?

    /// Whether anything has been typed into the interview's own fields, beyond what the calendar
    /// sync fills in (candidate, role, date).
    public var hasWrittenText: Bool {
        ![problemName, whiteboardLink, rawNotes, upsides, riskFactors, levelAssessment, conclusion,
            debriefNotes,
        ].allSatisfy { $0?.isEmpty ?? true }
    }

    /// True when nothing has been written beyond what the calendar sync auto-fills, so the
    /// interview can be discarded if its calendar event is cancelled.
    public var isEmpty: Bool {
        !hasWrittenText
            && recommendation == nil
            && (todos ?? []).isEmpty
            && debriefDate == nil
    }

    #Index<Interview>([\.date])

    public init(
        date: Date,
        candidateName: String,
        role: String? = nil
    ) {
        self.date = date
        self.candidateName = candidateName
        self.role = role
    }
}
