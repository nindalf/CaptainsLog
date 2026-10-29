import SwiftUI
import SwiftData
import CaptainsLogKit

/// The todos filed against one meeting or interview, as a section of its detail page, plus the
/// open todos that tag its people: a meeting's attendees, or the person a person page shows. A
/// meeting also keeps the todos checked off in it. Open todos come first, then completed ones. The host's Cmd+N bumps `addTick` to open a draft card on top.
struct LinkedTodoList: View {
    var addTick: Int
    private let title: String
    /// Files a committed draft against the meeting or interview. Nil on a person page, which
    /// only lists todos: a tag in the text, not the page, decides who a todo is linked to.
    private let attach: ((Todo) -> Void)?
    /// Stamped on a todo checked off here, so it stays in this meeting's list once completed.
    private let meeting: Meeting?
    private let peopleIDs: Set<UUID>
    /// Names the tagged people under each title, so a meeting shows who each todo is for.
    private let namesTaggedPeople: Bool

    // Filtered queries rather than `meeting.todos`, which does not notice inserts from the todo side.
    @Query private var linkedTodos: [Todo]
    @Query private var completedHere: [Todo]
    @Query(filter: #Predicate<Todo> { $0.completedDate == nil }, sort: \.sortOrder) private var openTodos: [Todo]
    @Query(sort: \Project.name) private var projects: [Project]

    @Environment(\.modelContext) private var modelContext
    @State private var draft: Todo?
    @State private var expandedID: UUID?
    @State private var showsAll = false
    @FocusState private var focusedField: TodoFocusField?

    init(meeting: Meeting, addTick: Int) {
        let id = meeting.id
        _linkedTodos = Query(filter: #Predicate<Todo> { $0.trashedDate == nil && $0.meeting?.id == id }, sort: \.sortOrder)
        _completedHere = Query(filter: #Predicate<Todo> {
            $0.trashedDate == nil && $0.completedDate != nil && $0.completedInMeeting?.id == id
        }, sort: \.sortOrder)
        self.addTick = addTick
        title = "Todos"
        // A todo copies its meeting's or interview's privacy once, when filed.
        attach = { $0.meeting = meeting; $0.isPrivate = meeting.isPrivate }
        self.meeting = meeting
        peopleIDs = Set(meeting.attendees.map(\.id))
        namesTaggedPeople = true
    }

    init(interview: Interview, addTick: Int) {
        let id = interview.id
        _linkedTodos = Query(filter: #Predicate<Todo> { $0.trashedDate == nil && $0.interview?.id == id }, sort: \.sortOrder)
        _completedHere = Query(filter: #Predicate<Todo> { _ in false })
        self.addTick = addTick
        title = "Todos"
        attach = { $0.interview = interview; $0.isPrivate = interview.isPrivate }
        meeting = nil
        peopleIDs = []
        namesTaggedPeople = false
    }

    init(person: Person) {
        _linkedTodos = Query(filter: #Predicate<Todo> { _ in false })
        _completedHere = Query(filter: #Predicate<Todo> { _ in false })
        addTick = 0
        title = "Open Todos"
        attach = nil
        meeting = nil
        peopleIDs = [person.id]
        namesTaggedPeople = false
    }

    /// Open todos tagging any of `peopleIDs` that aren't filed here already, in the People list's
    /// order (`TodoPeopleGroup`), so rows with the same label sit together.
    private var taggedTodos: [Todo] {
        guard !peopleIDs.isEmpty else { return [] }
        let linkedIDs = Set(linkedTodos.map(\.id))
        var tagged: [(todo: Todo, names: [String])] = []
        for todo in openTodos where !todo.isTrashed && !linkedIDs.contains(todo.id) {
            let names = taggedPeopleNames(todo)
            if !names.isEmpty { tagged.append((todo, names)) }
        }
        tagged.sort { lhs, rhs in
            if lhs.names != rhs.names { return TodoPeopleGroup.precedes(lhs.names, rhs.names) }
            return lhs.todo.sortOrder < rhs.todo.sortOrder
        }
        return tagged.map(\.todo)
    }

    private func taggedPeopleNames(_ todo: Todo) -> [String] {
        TodoPeopleGroup.names(of: todo, among: peopleIDs)
    }

    /// Completed todos filed here, and those checked off here though filed elsewhere or not at all.
    private var completedTodos: [Todo] {
        let linked = linkedTodos.filter(\.isCompleted)
        let linkedIDs = Set(linked.map(\.id))
        return (linked + completedHere.filter { !linkedIDs.contains($0.id) }).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var orderedTodos: [Todo] {
        linkedTodos.filter { !$0.isCompleted } + taggedTodos + completedTodos
    }

    /// Past this many, the rest wait behind a Show More row. Completed todos sort last, so they
    /// are the first hidden.
    private static let collapsedCount = 5

    private var visibleTodos: [Todo] {
        showsAll ? orderedTodos : Array(orderedTodos.prefix(Self.collapsedCount))
    }

    private func taggedNames(_ todo: Todo) -> String? {
        guard namesTaggedPeople else { return nil }
        let names = taggedPeopleNames(todo)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    var body: some View {
        // Always present where todos can be added, so the page's structure doesn't change when one
        // is: rebuilding it would take focus from the text view being typed in, as when the
        // scorecard todo appears.
        if attach != nil || !orderedTodos.isEmpty {
            section
        }
    }

    private var section: some View {
        DetailSection(title) {
            if attach != nil {
                Button(action: createDraft) {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Add Todo (⌘N)")
            }
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                if let draft {
                    card(for: draft)
                } else if orderedTodos.isEmpty {
                    Button("Add Todo", systemImage: "plus") { createDraft() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                ForEach(visibleTodos) { todo in
                    if expandedID == todo.id {
                        card(for: todo)
                    } else {
                        row(for: todo)
                    }
                }
                if orderedTodos.count > Self.collapsedCount {
                    Button(showsAll ? "Show Less" : "Show \(orderedTodos.count - Self.collapsedCount) More") {
                        showsAll.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
                    .padding(.vertical, 2)
                }
            }
        }
        .onChange(of: addTick) { createDraft() }
        .onDisappear { collapseAndCommit() }
    }

    private func row(for todo: Todo) -> some View {
        TodoRowView(
            todo: todo,
            isSelected: false,
            isCompleting: false,
            showsSource: false,
            trailing: taggedNames(todo),
            compact: true,
            onSelect: { expand(todo) },
            onExpand: { expand(todo) },
            onComplete: { toggleComplete(todo) }
        )
        .contextMenu {
            Button("Move to Trash", systemImage: "trash") {
                todo.moveToTrash()
                try? modelContext.save()
            }
        }
    }

    private func card(for todo: Todo) -> some View {
        TodoCardView(
            todo: todo,
            projects: projects,
            focusedField: $focusedField,
            onComplete: { if todo !== draft { toggleComplete(todo) } },
            onCollapse: { collapseAndCommit() },
            onDelete: todo === draft ? nil : {
                expandedID = nil
                todo.moveToTrash()
                try? modelContext.save()
            }
        )
        .onKeyPress(.escape) {
            collapseAndCommit()
            return .handled
        }
    }

    private func createDraft() {
        guard attach != nil else { return }
        collapseAndCommit()
        let newDraft = Todo(title: "")
        SmartList.inbox.move(newDraft)
        newDraft.sortOrder = TodoOrdering.topSortOrder(among: openTodos)
        draft = newDraft
        // The card only exists after this update, so focus it on the next one.
        Task { focusedField = .title(newDraft.id) }
    }

    /// Saves a draft with a title and files it; an untitled draft is dropped. Relating the draft
    /// earlier would insert it even if it were then abandoned.
    private func commitDraft() {
        guard let draft else { return }
        if !draft.title.trimmingCharacters(in: .whitespaces).isEmpty {
            modelContext.insert(draft)
            attach?(draft)
        }
        self.draft = nil
    }

    private func collapseAndCommit() {
        commitDraft()
        expandedID = nil
        focusedField = nil
        try? modelContext.save()
    }

    private func expand(_ todo: Todo) {
        commitDraft()
        expandedID = todo.id
        focusedField = .title(todo.id)
    }

    private func toggleComplete(_ todo: Todo) {
        if todo.isCompleted {
            todo.reopen()
        } else {
            todo.completedDate = .now
            todo.completedInMeeting = meeting
        }
        try? modelContext.save()
    }
}
