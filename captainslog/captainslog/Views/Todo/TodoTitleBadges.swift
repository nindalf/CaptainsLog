import AppKit
import SwiftUI
import CaptainsLogKit

/// The badges after a collapsed todo's title, as in Things: one for notes, and a link to the
/// meeting or interview the todo was filed against, or to the pull request on GitHub. Each is a
/// `RecordBadge` in its kind's colour, with a tooltip.
struct TodoTitleBadges: View {
    let todo: Todo
    /// Off inside the meeting or interview itself, where the link would lead back to the same page.
    var showsSource: Bool = true
    @Environment(Navigator.self) private var navigator

    var body: some View {
        HStack(spacing: 5) {
            if todo.notes?.isEmpty == false {
                RecordBadge(icon: "doc.text", help: "Has notes")
            }
            if showsSource {
                if let meeting = todo.meeting {
                    RecordBadge(.meeting, help: "From the meeting \(meeting.title). Click to open it") {
                        navigator.openMeeting(meeting)
                    }
                } else if let interview = todo.interview {
                    RecordBadge(.interview, help: "From the interview with \(interview.candidateName). Click to open it") {
                        navigator.openInterview(interview)
                    }
                }
                if let pullRequest = todo.pullRequest {
                    RecordBadge(.pullRequest, help: "About #\(pullRequest.number). Click to open it on GitHub") {
                        NSWorkspace.shared.open(pullRequest.url)
                    }
                }
            }
        }
    }
}
