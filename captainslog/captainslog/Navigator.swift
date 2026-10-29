import SwiftUI
import CaptainsLogKit

/// Owns the sidebar selection and the detail column's navigation path so any view can open a
/// person, meeting or interview without threading bindings through every intermediate view.
@Observable
@MainActor
final class Navigator {
    var selectedItem: SidebarItem? = .dashboard
    var path = NavigationPath()
    /// The Todos tab's list or project. Lives here so it survives tab switches.
    var todoSelection: TodoSelection = .smart(.today)
    /// A just-created project whose title should take focus for renaming.
    var renamingProjectID: UUID?
    /// A todo for the Todos tab to select and scroll to once it shows the todo's list.
    var revealTodoID: UUID?
    /// The Search tab's query. Lives here so a search survives opening a todo or project in another tab.
    var searchQuery = ""

    /// Switching tabs starts a fresh stack -- the old path belongs to the tab we left.
    func select(_ item: SidebarItem?) {
        guard item != selectedItem else { return }
        path = NavigationPath()
        selectedItem = item
    }

    func openPerson(_ person: Person) { push(person) }
    func openMeeting(_ meeting: Meeting) { push(meeting) }
    func openInterview(_ interview: Interview) { push(interview) }

    /// Leaving a focused view, such as the todo list, hands focus to the new page's first field
    /// with its text selected, so a keystroke would replace a person's name or a meeting's title.
    /// Focus is dropped once the page is up, since SwiftUI moves it after the push.
    private func push<Value: Hashable>(_ value: Value) {
        path.append(value)
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

    /// Switches to the Todos tab, on the todo's home list, with the todo selected.
    func openTodo(_ todo: Todo) {
        todoSelection = .smart(SmartList.of(todo))
        revealTodoID = todo.id
        select(.todos)
    }

    func openProject(_ project: Project) {
        todoSelection = .project(project.id)
        select(.todos)
    }

    /// Opens the meeting or interview an event is linked to, if any.
    func openEvent(_ event: CalendarEvent) {
        if let meeting = event.meeting {
            openMeeting(meeting)
        } else if let interview = event.interview {
            openInterview(interview)
        }
    }
}

/// What the Todos tab shows: a smart list, or one project's todos. Projects are held by id;
/// models are not Sendable and the project may be deleted while selected.
enum TodoSelection: Hashable {
    case smart(SmartList)
    case project(UUID)

    var smartList: SmartList? {
        if case .smart(let list) = self { list } else { nil }
    }

    var projectID: UUID? {
        if case .project(let id) = self { id } else { nil }
    }

    var acceptsTodos: Bool {
        smartList?.acceptsTodos ?? true
    }
}
