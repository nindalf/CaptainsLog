import Foundation

/// What the Log tab's merged feed shows, and the date it files each record under. Shared so
/// `captains-log feed` lists the same records. Log entries always show.
public enum Feed {
    public static func includes(_ meeting: Meeting) -> Bool { meeting.notes?.isEmpty == false }
    public static func includes(_ interview: Interview) -> Bool { interview.rawNotes?.isEmpty == false }
    public static func includes(_ pr: PullRequest) -> Bool { pr.isAuthoredByMe }
    public static func includes(_ todo: Todo) -> Bool { todo.isCompleted && !todo.isTrashed }

    public static func date(of pr: PullRequest) -> Date { pr.mergedAt ?? pr.createdAt }
    public static func date(of todo: Todo) -> Date { todo.completedDate ?? .distantPast }
}
