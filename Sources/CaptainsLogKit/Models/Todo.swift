import Foundation
import SwiftData

@Model
public final class Todo {
    public var id: UUID = UUID()
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    /// Set when the todo is completed; nil while it is open.
    public var completedDate: Date?
    public var isCompleted: Bool { completedDate != nil }
    /// Set when the todo is moved to the Trash; it can be restored until the Trash is emptied.
    public var trashedDate: Date?
    public var isTrashed: Bool { trashedDate != nil }
    public var isPrivate: Bool = false
    public var sortOrder: Int = 0
    // Stored as a raw string, like PullRequest.stateRawValue. Defaults to anytime so todos
    // that predate smart lists land in Anytime rather than the Inbox.
    public var scheduleRawValue: String = TodoSchedule.anytime.rawValue
    public var schedule: TodoSchedule {
        get { TodoSchedule(rawValue: scheduleRawValue) ?? .anytime }
        set { scheduleRawValue = newValue.rawValue }
    }
    public var people: [Person] = []
    public var project: Project?
    public var meeting: Meeting?
    /// The meeting whose Todos section it was checked off in, so it stays listed there.
    public var completedInMeeting: Meeting?
    public var interview: Interview?
    public var pullRequest: PullRequest?

    #Index<Todo>([\.dueDate], [\.completedDate])

    public init(title: String, dueDate: Date? = nil) {
        self.title = title
        self.dueDate = dueDate
    }
}

extension Todo {
    /// Open and due before today.
    public func isOverdue(now: Date = .now) -> Bool {
        guard !isCompleted, let dueDate else { return false }
        let calendar = Calendar.current
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: now)
    }
}
