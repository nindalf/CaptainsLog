import SwiftUI
import CaptainsLogKit

/// The small icons after a collapsed todo's title, as in Things: one for notes, and a link to the
/// meeting or interview the todo was filed against, or to the pull request on GitHub.
struct TodoTitleBadges: View {
    let todo: Todo
    /// Off inside the meeting or interview itself, where the link would lead back to the same page.
    var showsSource: Bool = true
    @Environment(Navigator.self) private var navigator

    var body: some View {
        HStack(spacing: 5) {
            if todo.notes?.isEmpty == false {
                Image(systemName: "doc")
                    .help("Has notes")
            }
            if showsSource {
                if let meeting = todo.meeting {
                    sourceLink(Image(systemName: SidebarItem.meetings.icon), title: meeting.title) { navigator.openMeeting(meeting) }
                } else if let interview = todo.interview {
                    sourceLink(Image(systemName: SidebarItem.interviews.icon), title: interview.candidateName) { navigator.openInterview(interview) }
                }
                if let pullRequest = todo.pullRequest {
                    GitHubButton(pr: pullRequest)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func sourceLink(_ image: some View, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            image
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Open \(title)")
    }
}
