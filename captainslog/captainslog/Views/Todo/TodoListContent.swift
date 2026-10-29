import SwiftUI
import SwiftData
import CaptainsLogKit

/// The todo list proper: rows, drag reorder, drafts, keyboard. Shared by the Todos tab and the dashboard pane.
/// Shows one smart list or project; the add control lives in the host's toolbar, so it is an input.
struct TodoListContent: View {
    /// The list or project the host asks for; `scope` follows it.
    var requestedScope: TodoSelection
    /// Incremented by the host to request a new draft.
    var addTick: Int = 0
    var horizontalPadding: CGFloat = 16
    var focusesOnAppear: Bool = true
    /// When set, the list is only as tall as its rows, up to this height, rather than taking all
    /// the height on offer. The Dashboard sets it so a short Today leaves no gap.
    var fittedHeightLimit: CGFloat?
    @State private var contentHeight: CGFloat = 0

    /// The list or project shown. State rather than an input because SwiftUI keeps calling the
    /// `onKeyPress` closures from an earlier render, which would see a stale input after a switch.
    @State private var scope: TodoSelection

    init(
        scope: TodoSelection,
        addTick: Int = 0,
        horizontalPadding: CGFloat = 16,
        focusesOnAppear: Bool = true,
        fittedHeightLimit: CGFloat? = nil
    ) {
        self.requestedScope = scope
        self.addTick = addTick
        self.horizontalPadding = horizontalPadding
        self.focusesOnAppear = focusesOnAppear
        self.fittedHeightLimit = fittedHeightLimit
        _scope = State(initialValue: scope)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(Navigator.self) private var navigator

    @Query(sort: \Todo.sortOrder) private var allTodos: [Todo]
    @Query(sort: \Project.name) private var projects: [Project]

    /// The anchor row: keyboard actions and Shift-click ranges start here.
    @State private var selectedID: UUID?
    /// Every selected row, including the anchor. Cmd- and Shift-click grow it; the context menu acts on it.
    @State private var selection: Set<UUID> = []
    /// The moving end of a Shift+arrow range; the anchor stays put. Nil means it is at the anchor.
    @State private var cursorID: UUID?
    /// Todos the When popover will reschedule, shown on the row in `datePickerRowID`.
    @State private var datePickerTargetIDs: [UUID] = []
    @State private var datePickerRowID: UUID?
    /// Trashed todos awaiting confirmation before they are deleted for good.
    @State private var pendingPermanentDeleteIDs: [UUID] = []
    /// A completed project in the Logbook awaiting confirmation before it is deleted.
    @State private var projectToDelete: Project?
    @State private var expandedID: UUID?
    @State private var draft: Todo?
    @State private var draftInsertAfterID: UUID?
    /// The project a draft created inside a project joins once it is saved.
    @State private var draftProjectID: UUID?
    @State private var completingIDs: Set<UUID> = []
    @State private var pendingReopen: [Todo] = []
    @State private var draggingID: UUID?
    /// The dragged row's top in the layout from before the drag.
    @State private var dragStartTop: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    /// The list's rows and headings in the order the drag has made so far.
    @State private var liveItems: [TodoListItem]?
    @FocusState private var focusedField: TodoFocusField?

    // Drag positions are worked out from these, so rows and headings keep exactly these heights.
    private let rowHeight: CGFloat = 44
    private let headingHeight: CGFloat = 48

    /// Every open todo, in `sortOrder`, whatever list it is in.
    private var openTodos: [Todo] {
        allTodos.filter { !$0.isCompleted }
    }

    /// Open todos in this list or project, in `sortOrder`. Empty for the Logbook; the Trash lists
    /// everything trashed, most recent first.
    // Projects filter the query rather than reading `project.todos`, which does not notice inserts.
    private var activeTodos: [Todo] {
        switch scope {
        case .smart(.logbook):
            return []
        case .smart(.trash):
            return allTodos.filter(\.isTrashed).sorted {
                ($0.trashedDate ?? .distantPast) > ($1.trashedDate ?? .distantPast)
            }
        case .smart(let list):
            let now = Date.now
            return allTodos.filter { list.contains($0, now: now) }
        case .project(let id):
            return allTodos.filter { !$0.isCompleted && !$0.isTrashed && $0.project?.id == id }
        }
    }

    /// The Logbook is ordered by completion and the Trash by deletion, so only the others reorder.
    /// Dragging in Upcoming can also change a todo's date.
    private var isReorderable: Bool {
        scope != .smart(.logbook) && scope != .smart(.trash)
    }

    /// Today, Anytime and Someday group their todos under project headings, as in Things.
    private var isGroupedByProject: Bool {
        scope == .smart(.today) || scope == .smart(.anytime) || scope == .smart(.someday)
    }

    /// People groups its todos by who they tag. Todos can't move between those groups: the tags
    /// in the text decide them.
    private var isGroupedByPeople: Bool {
        scope == .smart(.people)
    }

    /// Open todos' rows, with project headings in the grouped lists, date headings in Upcoming and
    /// people headings in People, before any drag.
    private var staticItems: [TodoListItem] {
        if scope == .smart(.upcoming) { return TodoUpcomingGroup.items(upcomingGroups) }
        if isGroupedByPeople {
            return TodoPeopleGroup.group(activeTodos).flatMap { group in
                [TodoListItem.group(group.label)] + group.todos.map { .todo($0.id) }
            }
        }
        guard isGroupedByProject else { return activeTodos.map { .todo($0.id) } }
        return TodoProjectGroup.group(activeTodos).flatMap { group in
            (group.project.map { [TodoListItem.heading($0.id)] } ?? []) + group.todos.map { .todo($0.id) }
        }
    }

    private var listItems: [TodoListItem] {
        liveItems ?? staticItems
    }

    /// Open todos in on-screen order.
    private var displayedActive: [Todo] {
        let lookup = Dictionary(uniqueKeysWithValues: activeTodos.map { ($0.id, $0) })
        return listItems.compactMap { $0.todoID.flatMap { lookup[$0] } }
    }

    /// Most recently completed first: the Logbook's todos, or a project's completed ones.
    private var completedTodos: [Todo] {
        let completed: [Todo]
        switch scope {
        case .smart(.logbook): completed = allTodos.filter { $0.isCompleted && !$0.isTrashed }
        case .project(let id): completed = allTodos.filter { $0.isCompleted && !$0.isTrashed && $0.project?.id == id }
        case .smart: return []
        }
        return completed.sorted {
            ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast)
        }
    }

    /// Completed projects are listed in the Logbook rather than the column.
    private var logbookGroups: [TodoLogbookGroup] {
        let completedProjects = scope == .smart(.logbook) ? projects.filter(\.isCompleted) : []
        return TodoLogbookGroup.group(completedTodos, projects: completedProjects)
    }

    private var upcomingGroups: [TodoUpcomingGroup] {
        TodoUpcomingGroup.group(activeTodos)
    }

    /// Rows in on-screen order, for keyboard navigation.
    private var displayedTodos: [Todo] {
        switch scope {
        case .smart(.logbook): logbookGroups.flatMap(\.todos)
        case .project: displayedActive + completedTodos
        case .smart: displayedActive
        }
    }

    private var selectedTodo: Todo? {
        guard let selectedID else { return nil }
        return displayedTodos.first { $0.id == selectedID }
    }

    /// Every selected row, in on-screen order. Keyboard actions apply to these.
    private var selectedTodos: [Todo] {
        displayedTodos.filter { selection.contains($0.id) }
    }

    var body: some View {
        todoScrollView
            .onChange(of: addTick) { createDraft(below: false) }
            .reopenConfirmation($pendingReopen)
            .alert(
                pendingPermanentDeleteIDs.count == 1 ? "Delete this to-do permanently?" : "Delete \(pendingPermanentDeleteIDs.count) to-dos permanently?",
                isPresented: Binding(get: { !pendingPermanentDeleteIDs.isEmpty }, set: { if !$0 { pendingPermanentDeleteIDs = [] } })
            ) {
                Button("Delete", role: .destructive) { deletePermanently(pendingPermanentDeleteIDs) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            .alert(
                "Delete \"\(projectToDelete?.name ?? "")\"?",
                isPresented: Binding(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }),
                presenting: projectToDelete
            ) { project in
                Button("Delete", role: .destructive) {
                    modelContext.delete(project)
                    try? modelContext.save()
                }
                Button("Cancel", role: .cancel) {}
            } message: { project in
                Text(project.deletionSummary)
            }
            .onChange(of: requestedScope) {
                commitDraft()
                scope = requestedScope
                expandedID = nil
                select(nil)
                liveItems = nil
            }
    }

    // MARK: - View hierarchy

    private var todoScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                todoListContent
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: fittedHeightLimit.map { min(contentHeight, $0) })
            .onAppear { revealRequestedTodo(proxy) }
            .onChange(of: navigator.revealTodoID) { revealRequestedTodo(proxy) }
        }
        .contentShape(Rectangle())
        .onTapGesture { collapseAndCommit() }
        .focusable()
        .focusEffectDisabled()
        .focused($focusedField, equals: .list)
        .onAppear { if focusesOnAppear { focusedField = .list } }
        .onKeyPress(.return, phases: .down) { handleReturnKey($0) }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { handleUpArrow($0) }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { handleDownArrow($0) }
        .onKeyPress(.space) { handleSpace() }
        // The Delete key arrives as U+007F, which neither `.delete` nor `.deleteForward` matches;
        // `.deleteForward` matches only Fn-Delete.
        .onKeyPress(phases: .down) { press in
            press.characters == "\u{7F}" || press.key == .deleteForward ? handleDelete() : .ignored
        }
        .onKeyPress("k", phases: .down) { handleK($0) }
        .onKeyPress("a", phases: .down) { handleA($0) }
    }

    private var todoListContent: some View {
        LazyVStack(spacing: 0) {
            draftCardAtTop

            if scope == .smart(.trash) && !activeTodos.isEmpty {
                emptyTrashButton
            }

            switch scope {
            case .smart(.logbook):
                ForEach(logbookGroups) { group in
                    groupHeader(group.label)
                    ForEach(group.entries) { entry in
                        switch entry {
                        case .todo(let todo): todoRow(for: todo)
                        case .project(let project): completedProjectRow(project)
                        }
                    }
                }
            default:
                let lookup = Dictionary(uniqueKeysWithValues: activeTodos.map { ($0.id, $0) })
                let peopleByLabel = isGroupedByPeople
                    ? Dictionary(uniqueKeysWithValues: TodoPeopleGroup.group(activeTodos).map { ($0.label, $0.people) })
                    : [:]
                ForEach(listItems, id: \.self) { item in
                    switch item {
                    case .heading(let id):
                        projectHeading(id)
                    case .group(let label):
                        if let people = peopleByLabel[label] {
                            peopleHeading(people)
                        } else {
                            groupHeader(label)
                        }
                    case .todo(let id):
                        if let todo = lookup[id] {
                            todoRow(for: todo)
                            draftCard(after: todo)
                        }
                    }
                }
                if scope.projectID != nil && !completedTodos.isEmpty {
                    groupHeader("Completed")
                    ForEach(completedTodos) { todo in
                        todoRow(for: todo)
                    }
                }
            }

            if displayedTodos.isEmpty && draft == nil && logbookGroups.isEmpty {
                emptyState
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity)
        .coordinateSpace(name: "todoList")
        .animation(.snappy(duration: 0.18), value: liveItems)
    }

    private var emptyTrashButton: some View {
        HStack {
            Spacer()
            Button("Empty Trash") {
                pendingPermanentDeleteIDs = activeTodos.map(\.id)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        Image(systemName: scope.smartList?.systemImage ?? "list.bullet.circle")
            .font(.system(size: 40))
            .foregroundStyle(.quaternary)
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
    }

    // MARK: - Group headers

    /// A project's heading in Anytime and Someday. Clicking it opens the project.
    @ViewBuilder
    private func projectHeading(_ id: UUID) -> some View {
        if let project = projects.first(where: { $0.id == id }) {
            Button { navigator.todoSelection = .project(id) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: project.icon)
                            .foregroundStyle(.blue)
                        Text(project.name)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Divider()
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: headingHeight, maxHeight: headingHeight, alignment: .bottomLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// A completed project in the Logbook, laid out like a completed todo. Clicking opens it.
    private func completedProjectRow(_ project: Project) -> some View {
        Button { navigator.todoSelection = .project(project.id) } label: {
            HStack(spacing: 12) {
                Text(project.completedDate?.formatted(.dateTime.day().month(.abbreviated)) ?? "")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 46, alignment: .trailing)
                Image(systemName: project.icon)
                    .foregroundStyle(.secondary)
                Text(project.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 40)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reopen Project") {
                ProjectCompletion.reopen(project)
                try? modelContext.save()
            }
            Divider()
            Button("Delete Project…", role: .destructive) { projectToDelete = project }
        }
    }

    /// A section heading in People. Each name opens that person, as project headings open the
    /// project. Drags measure it, so it keeps exactly `headingHeight`.
    private func peopleHeading(_ people: [Person]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PersonLinks(people: people)
                .font(.headline)
                .tint(.primary)
                .lineLimit(1)
            Divider()
        }
        .padding(.bottom, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: headingHeight, maxHeight: headingHeight, alignment: .bottomLeading)
    }

    /// A date heading: in Upcoming it is a drag target, so it keeps exactly `headingHeight`.
    private func groupHeader(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.headline)
            Divider()
        }
        .padding(.bottom, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: headingHeight, maxHeight: headingHeight, alignment: .bottomLeading)
    }

    @ViewBuilder
    private var draftCardAtTop: some View {
        if let draft, draftInsertAfterID == nil {
            TodoCardView(todo: draft, projects: projects, focusedField: $focusedField, onComplete: {}, onCollapse: { collapseAndCommit() })
                .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func draftCard(after todo: Todo) -> some View {
        if let draft, draftInsertAfterID == todo.id {
            TodoCardView(todo: draft, projects: projects, focusedField: $focusedField, onComplete: {}, onCollapse: { collapseAndCommit() })
                .padding(.vertical, 2)
        }
    }

    // MARK: - Row builder

    /// Identified by the todo, so a todo opened from elsewhere can be scrolled to.
    private func todoRow(for todo: Todo) -> some View {
        todoRowContent(for: todo).id(todo.id)
    }

    @ViewBuilder
    private func todoRowContent(for todo: Todo) -> some View {
        if completingIDs.contains(todo.id) {
            TodoRowView(
                todo: todo,
                isSelected: false,
                isCompleting: true,
                subtitle: projectName(for: todo),
                onSelect: {},
                onExpand: {},
                onComplete: {}
            )
            .opacity(0.4)
        } else if expandedID == todo.id {
            TodoCardView(
                todo: todo,
                projects: projects,
                focusedField: $focusedField,
                onComplete: { toggleComplete(todo) },
                onCollapse: { collapseAndCommit() },
                onDelete: { trash([todo]) }
            )
            .padding(.vertical, 2)
            .contextMenu { todoContextMenu(todo) }
            .popover(isPresented: datePickerBinding(for: todo)) { whenPopover() }
        } else if todo.isCompleted {
            CompletedTodoRowView(
                todo: todo,
                isSelected: selection.contains(todo.id),
                showsProject: scope.projectID == nil,
                onSelect: { handleRowClick(todo) },
                onExpand: { expandTodo(todo) },
                onComplete: { toggleComplete(todo) }
            )
            .contextMenu { todoContextMenu(todo) }
        } else {
            collapsedRow(for: todo)
                .contextMenu { todoContextMenu(todo) }
                .popover(isPresented: datePickerBinding(for: todo)) { whenPopover() }
        }
    }

    /// Smart lists name a todo's project under its title; a project's own list doesn't repeat it.
    private func projectName(for todo: Todo) -> String? {
        scope.projectID == nil && !isGroupedByProject ? todo.project?.name : nil
    }

    private func collapsedRow(for todo: Todo) -> some View {
        TodoRowView(
            todo: todo,
            isSelected: selection.contains(todo.id),
            isCompleting: false,
            showsTodayStar: (scope.projectID != nil || scope == .smart(.anytime)) && SmartList.today.contains(todo),
            subtitle: projectName(for: todo),
            onSelect: { handleRowClick(todo) },
            onExpand: { expandTodo(todo) },
            onComplete: { toggleComplete(todo) }
        )
        .offset(y: draggingID == todo.id ? draggedRowOffset(for: todo) : 0)
        .zIndex(draggingID == todo.id ? 1 : 0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("todoList"))
                .onChanged { value in handleDragChanged(todo: todo, translation: value.translation.height) }
                .onEnded { _ in handleDragEnded() },
            including: isReorderable ? .all : .subviews
        )
    }

    // MARK: - Context menu

    /// Right-clicking a selected row acts on the whole selection; any other row acts alone.
    private func contextTargets(for todo: Todo) -> [Todo] {
        guard selection.contains(todo.id), selection.count > 1 else { return [todo] }
        return displayedTodos.filter { selection.contains($0.id) }
    }

    @ViewBuilder
    private func todoContextMenu(_ todo: Todo) -> some View {
        let targets = contextTargets(for: todo)
        if scope == .smart(.trash) {
            trashContextMenu(targets)
        } else {
            listContextMenu(for: todo, targets: targets)
        }
    }

    @ViewBuilder
    private func trashContextMenu(_ targets: [Todo]) -> some View {
        Button(targets.count > 1 ? "Restore \(targets.count) To-Dos" : "Restore", systemImage: "arrow.uturn.backward") {
            apply(to: targets) { $0.restoreFromTrash() }
        }
        Divider()
        Button(targets.count > 1 ? "Delete \(targets.count) To-Dos Permanently…" : "Delete Permanently…", role: .destructive) {
            pendingPermanentDeleteIDs = targets.map(\.id)
        }
    }

    @ViewBuilder
    private func listContextMenu(for todo: Todo, targets: [Todo]) -> some View {
        if targets.allSatisfy({ !$0.isCompleted }) {
            Button("When…", systemImage: "calendar") {
                commitDraft()
                datePickerTargetIDs = targets.map(\.id)
                datePickerRowID = todo.id
            }
        }
        Menu("Project") {
            Button("No Project") { apply(to: targets) { $0.project = nil } }
            let open = projects.filter { !$0.isCompleted }
            if !open.isEmpty { Divider() }
            ForEach(open) { project in
                Button(project.name) { apply(to: targets) { $0.project = project } }
            }
        }
        Divider()
        Button(targets.count > 1 ? "Move \(targets.count) To-Dos to Trash" : "Move to Trash", systemImage: "trash") {
            commitDraft()
            trash(targets)
        }
    }

    private func apply(to todos: [Todo], _ change: (Todo) -> Void) {
        commitDraft()
        todos.forEach(change)
        try? modelContext.save()
    }

    /// The When popover, anchored on the row that was right-clicked.
    private func datePickerBinding(for todo: Todo) -> Binding<Bool> {
        Binding(
            get: { datePickerRowID == todo.id },
            set: { if !$0 { datePickerRowID = nil } }
        )
    }

    private func whenPopover() -> some View {
        TodoWhenPopover(todos: allTodos.filter { datePickerTargetIDs.contains($0.id) }) {
            try? modelContext.save()
            datePickerRowID = nil
        }
    }

    // MARK: - Draft management

    private func createDraft(below: Bool) {
        guard scope.acceptsTodos else { return }
        commitDraft()
        let newDraft = Todo(title: "")
        scope.smartList?.move(newDraft)
        // The project is set in commitDraft: relating an unsaved draft to a saved project would
        // insert the draft immediately, even if it is then abandoned empty. Below a todo in a
        // project group, the draft joins that project.
        draftProjectID = scope.projectID
        if below, isGroupedByProject {
            draftProjectID = selectedTodo?.project?.id
        }
        // Below a todo in Upcoming, the draft takes its date so it stays where it was created.
        if below, scope == .smart(.upcoming), let date = selectedTodo?.dueDate {
            newDraft.dueDate = date
        }
        // Positions come from the order across all open todos, not just this list, so they
        // stay unique when the todo later moves to another list.
        if below, isReorderable, let selected = selectedTodo {
            TodoOrdering.makeUnique(openTodos)
            let anchor = selected.sortOrder
            for todo in openTodos where todo.sortOrder > anchor {
                todo.sortOrder += 1
            }
            newDraft.sortOrder = anchor + 1
            draftInsertAfterID = selected.id
        } else {
            newDraft.sortOrder = TodoOrdering.topSortOrder(among: openTodos)
            draftInsertAfterID = nil
        }
        draft = newDraft
        expandedID = nil
        focusedField = .title(newDraft.id)
    }

    private func commitDraft() {
        guard let draft else { return }
        let title = draft.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            modelContext.insert(draft)
            if let draftProjectID {
                draft.project = projects.first { $0.id == draftProjectID }
            }
            try? modelContext.save()
        }
        self.draft = nil
        draftInsertAfterID = nil
        draftProjectID = nil
    }

    private func collapseAndCommit() {
        withAnimation(.snappy(duration: 0.15)) {
            expandedID = nil
        }
        commitDraft()
        focusedField = .list
    }

    // MARK: - Todo actions

    private func expandTodo(_ todo: Todo) {
        commitDraft()
        select(todo.id)
        withAnimation(.snappy(duration: 0.15)) {
            expandedID = todo.id
        }
        focusedField = .title(todo.id)
    }

    private func toggleComplete(_ todo: Todo) {
        setCompleted([todo], !todo.isCompleted)
    }

    /// Completing waits briefly so the checked rows show before they leave the list.
    private func setCompleted(_ todos: [Todo], _ completed: Bool) {
        guard completed else {
            ReopenConfirmation.request(todos, pending: &pendingReopen, in: modelContext)
            return
        }
        let completing = todos.filter { !$0.isCompleted && !completingIDs.contains($0.id) }
        guard !completing.isEmpty else { return }
        let ids = Set(completing.map(\.id))
        completingIDs.formUnion(ids)
        if let expandedID, ids.contains(expandedID) {
            withAnimation(.snappy(duration: 0.15)) { self.expandedID = nil }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            for todo in completing {
                todo.completedDate = .now
            }
            completingIDs.subtract(ids)
            try? modelContext.save()
        }
    }

    /// Delete moves todos to the Trash; only the Trash deletes for good.
    private func trash(_ todos: [Todo]) {
        guard !todos.isEmpty else { return }
        let ids = Set(todos.map(\.id))
        if let expandedID, ids.contains(expandedID) { self.expandedID = nil }
        let nextID = nextSelection(afterRemoving: ids)
        todos.forEach { $0.moveToTrash() }
        try? modelContext.save()
        select(nextID)
    }

    private func deletePermanently(_ ids: [UUID]) {
        for todo in allTodos where ids.contains(todo.id) && todo.isTrashed {
            modelContext.delete(todo)
        }
        try? modelContext.save()
        select(nil)
    }

    /// The first remaining row below the removed ones, else the nearest one above.
    private func nextSelection(afterRemoving ids: Set<UUID>) -> UUID? {
        let todos = displayedTodos
        guard let last = todos.lastIndex(where: { ids.contains($0.id) }) else { return nil }
        if let below = todos[(last + 1)...].first(where: { !ids.contains($0.id) }) { return below.id }
        return todos[..<last].last(where: { !ids.contains($0.id) })?.id
    }

    /// Selects and scrolls to the todo another tab asked to open (`Navigator.openTodo`), if this list shows it.
    private func revealRequestedTodo(_ proxy: ScrollViewProxy) {
        guard let id = navigator.revealTodoID, displayedTodos.contains(where: { $0.id == id }) else { return }
        navigator.revealTodoID = nil
        select(id)
        proxy.scrollTo(id, anchor: .center)
    }

    // MARK: - Selection & reorder

    /// Select a single row (or none), dropping any multiple selection.
    private func select(_ id: UUID?) {
        selectedID = id
        cursorID = nil
        selection = id.map { [$0] } ?? []
    }

    /// Selects every row from the anchor to `id`, keeping the anchor.
    private func selectRange(to id: UUID) {
        let todos = displayedTodos
        guard let anchor = selectedID,
              let from = todos.firstIndex(where: { $0.id == anchor }),
              let to = todos.firstIndex(where: { $0.id == id }) else { return }
        cursorID = id
        selection = Set(todos[min(from, to)...max(from, to)].map(\.id))
    }

    /// Plain click selects one row; Cmd-click toggles a row; Shift-click selects the range from the anchor.
    private func handleRowClick(_ todo: Todo) {
        collapseAndCommit()
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift), let anchor = selectedID,
           displayedTodos.contains(where: { $0.id == anchor }) {
            selectRange(to: todo.id)
            return
        }
        if modifiers.contains(.command) {
            cursorID = nil
            if selection.contains(todo.id) {
                selection.remove(todo.id)
                if selectedID == todo.id { selectedID = selection.first }
            } else {
                selection.insert(todo.id)
                selectedID = todo.id
            }
            return
        }
        select(todo.id)
    }

    /// The row a plain or Shift+arrow press moves from, `delta` rows on; the first or last row
    /// when nothing on screen is selected.
    private func rowID(movingCursorBy delta: Int) -> UUID? {
        let todos = displayedTodos
        guard !todos.isEmpty else { return nil }
        let index = [cursorID, selectedID].compactMap { $0 }.lazy
            .compactMap { id in todos.firstIndex { $0.id == id } }.first
        if let index {
            return todos[max(0, min(todos.count - 1, index + delta))].id
        }
        return delta > 0 ? todos.first?.id : todos.last?.id
    }

    /// Plain arrows collapse any range back to one row.
    private func moveSelection(by delta: Int) {
        guard let id = rowID(movingCursorBy: delta) else { return }
        select(id)
    }

    /// Shift+arrows grow or shrink the range from the anchor.
    private func extendSelection(by delta: Int) {
        guard let id = rowID(movingCursorBy: delta) else { return }
        if let selectedID, displayedTodos.contains(where: { $0.id == selectedID }) {
            selectRange(to: id)
        } else {
            select(id)
        }
    }

    private func reorderSelected(by delta: Int) {
        guard isReorderable else { return }
        TodoOrdering.makeUnique(openTodos)
        let todos = displayedTodos
        guard let selectedID,
              let index = todos.firstIndex(where: { $0.id == selectedID }) else { return }
        let newIndex = index + delta
        guard newIndex >= 0 && newIndex < todos.count else { return }
        // Keyboard moves stay within a project group; dragging moves todos between them. In People
        // neither does.
        if isGroupedByProject, todos[index].project?.id != todos[newIndex].project?.id { return }
        if isGroupedByPeople, TodoPeopleGroup.names(of: todos[index]) != TodoPeopleGroup.names(of: todos[newIndex]) { return }
        // Upcoming sorts by date first, so only todos on the same day can swap.
        if scope == .smart(.upcoming), todos[index].dueDate != todos[newIndex].dueDate { return }

        let temp = todos[index].sortOrder
        todos[index].sortOrder = todos[newIndex].sortOrder
        todos[newIndex].sortOrder = temp
        try? modelContext.save()
    }

    private func height(of item: TodoListItem) -> CGFloat {
        item.todoID == nil ? headingHeight : rowHeight
    }

    private func top(of id: UUID, in items: [TodoListItem]) -> CGFloat? {
        var y: CGFloat = 0
        for item in items {
            if item == .todo(id) { return y }
            y += height(of: item)
        }
        return nil
    }

    /// The dragged row goes before the first item whose middle is below the row's middle.
    private func handleDragChanged(todo: Todo, translation: CGFloat) {
        if draggingID == nil {
            guard expandedID == nil, draft == nil, isReorderable else { return }
            // handleDragEnded hands the list's existing values back out in the new order,
            // which is a no-op if they are all equal.
            TodoOrdering.makeUnique(openTodos)
            let items = staticItems
            guard let start = top(of: todo.id, in: items) else { return }
            draggingID = todo.id
            dragStartTop = start
            liveItems = items
        }
        dragTranslation = translation
        guard var items = liveItems, let index = items.firstIndex(of: .todo(todo.id)) else { return }
        items.remove(at: index)
        let middle = dragStartTop + translation + rowHeight / 2
        var y: CGFloat = 0
        var target = items.count
        for (i, item) in items.enumerated() {
            if middle < y + height(of: item) / 2 {
                target = i
                break
            }
            y += height(of: item)
        }
        // In Upcoming every todo sits under a date heading.
        if scope == .smart(.upcoming) { target = max(target, 1) }
        if isGroupedByPeople {
            let range = TodoPeopleGroup.dropRange(at: index, in: items)
            target = min(max(target, range.lowerBound), range.upperBound)
        }
        items.insert(.todo(todo.id), at: target)
        if items != liveItems { liveItems = items }
    }

    private func draggedRowOffset(for todo: Todo) -> CGFloat {
        guard let liveItems, let top = top(of: todo.id, in: liveItems) else { return 0 }
        return dragStartTop + dragTranslation - top
    }

    /// Hands the list's existing `sortOrder` values out in the dropped order. In the grouped lists
    /// the todo also joins the project whose heading it was dropped under, or leaves its project
    /// when dropped above every heading. In Upcoming it takes the date of where it was dropped.
    private func handleDragEnded() {
        if let liveItems {
            let source = activeTodos
            let lookup = Dictionary(uniqueKeysWithValues: source.map { ($0.id, $0) })
            if scope == .smart(.upcoming), let draggingID,
               let date = TodoUpcomingGroup.dueDate(for: draggingID, droppedIn: liveItems, groups: upcomingGroups),
               let todo = lookup[draggingID], todo.dueDate != date {
                todo.schedule(on: date)
            }
            let existingOrders = source.map(\.sortOrder)
            for (i, id) in liveItems.compactMap(\.todoID).enumerated() where i < existingOrders.count {
                lookup[id]?.sortOrder = existingOrders[i]
            }
            if isGroupedByProject, let draggingID, let todo = lookup[draggingID] {
                let projectID = TodoListItem.projectID(above: draggingID, in: liveItems)
                if todo.project?.id != projectID {
                    todo.project = projectID.flatMap { id in projects.first { $0.id == id } }
                }
            }
            try? modelContext.save()
        }
        withAnimation(.snappy(duration: 0.18)) {
            draggingID = nil
            dragStartTop = 0
            dragTranslation = 0
            liveItems = nil
        }
    }

    // MARK: - Key handlers

    private func handleReturnKey(_ keyPress: KeyPress) -> KeyPress.Result {
        if keyPress.modifiers.contains(.shift) {
            return .ignored
        }
        // Return closes an open card or a new draft; it opens the selected row only when neither is open.
        if expandedID != nil || draft != nil {
            collapseAndCommit()
            return .handled
        }
        guard let todo = selectedTodo else { return .ignored }
        expandTodo(todo)
        return .handled
    }

    private func handleUpArrow(_ keyPress: KeyPress) -> KeyPress.Result {
        handleArrow(keyPress, delta: -1)
    }

    private func handleDownArrow(_ keyPress: KeyPress) -> KeyPress.Result {
        handleArrow(keyPress, delta: 1)
    }

    private func handleArrow(_ keyPress: KeyPress, delta: Int) -> KeyPress.Result {
        // While a card is open, arrows belong to its text fields.
        guard expandedID == nil, draft == nil else { return .ignored }
        if keyPress.modifiers.contains(.command) {
            reorderSelected(by: delta)
        } else if keyPress.modifiers.contains(.shift) {
            extendSelection(by: delta)
        } else {
            moveSelection(by: delta)
        }
        return .handled
    }

    private func handleEscape() -> KeyPress.Result {
        if let draft {
            let title = draft.title.trimmingCharacters(in: .whitespaces)
            if title.isEmpty {
                self.draft = nil
                draftInsertAfterID = nil
            } else {
                collapseAndCommit()
            }
            focusedField = .list
            return .handled
        }
        if expandedID != nil {
            collapseAndCommit()
            return .handled
        }
        if selectedID != nil || !selection.isEmpty {
            select(nil)
            return .handled
        }
        return .ignored
    }

    private func handleSpace() -> KeyPress.Result {
        guard selectedID != nil, expandedID == nil, draft == nil else { return .ignored }
        createDraft(below: true)
        return .handled
    }

    private func handleDelete() -> KeyPress.Result {
        // In the Trash the Delete key does nothing: deleting for good goes through a confirmation.
        // While a card is open, Delete belongs to its text fields.
        let todos = selectedTodos
        guard scope != .smart(.trash), expandedID == nil, draft == nil, !todos.isEmpty else { return .ignored }
        trash(todos)
        return .handled
    }

    /// Completes the selection, or reopens it when every selected todo is already complete.
    private func handleK(_ keyPress: KeyPress) -> KeyPress.Result {
        guard keyPress.modifiers.contains(.command) else { return .ignored }
        let todos = selectedTodos
        guard !todos.isEmpty else { return .ignored }
        setCompleted(todos, !todos.allSatisfy(\.isCompleted))
        return .handled
    }

    private func handleA(_ keyPress: KeyPress) -> KeyPress.Result {
        guard keyPress.modifiers.contains(.command), expandedID == nil, draft == nil else { return .ignored }
        let todos = displayedTodos
        guard !todos.isEmpty else { return .ignored }
        if selectedTodo == nil { selectedID = todos.first?.id }
        cursorID = nil
        selection = Set(todos.map(\.id))
        return .handled
    }
}
