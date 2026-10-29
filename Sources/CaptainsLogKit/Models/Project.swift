import Foundation
import SwiftData

@Model
public final class Project {
    public var id: UUID = UUID()
    public var name: String
    public var notes: String?
    /// Set when the project is completed; nil while it is open.
    public var completedDate: Date?
    public var isCompleted: Bool { completedDate != nil }
    /// Position in the Todos tab's project list.
    public var sortOrder: Int = 0
    /// SF Symbol shown for the project; nil uses the app's default.
    public var iconName: String?

    // Inserting a second project with an existing name upserts and wipes relationships, so names
    // must come from ProjectNaming.
    #Unique<Project>([\.name])

    @Relationship(deleteRule: .nullify, inverse: \LogEntry.project)
    public var logEntries: [LogEntry]?
    @Relationship(deleteRule: .nullify, inverse: \Meeting.project)
    public var meetings: [Meeting]?
    @Relationship(deleteRule: .nullify, inverse: \PullRequest.project)
    public var pullRequests: [PullRequest]?
    @Relationship(deleteRule: .nullify, inverse: \Todo.project)
    public var todos: [Todo]?

    public init(name: String) {
        self.name = name
    }
}
