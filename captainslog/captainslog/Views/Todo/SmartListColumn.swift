import SwiftUI
import SwiftData
import CaptainsLogKit

/// The Todos tab's inner sidebar: Inbox, Today, Upcoming, Anytime, Someday, Logbook, then projects.
// Plain buttons rather than List(selection:): the list did not highlight the stored selection on
// launch, and it took arrow keys meant for the todo list beside it.
struct SmartListColumn: View {
    @Binding var selection: TodoSelection

    @Environment(\.modelContext) private var modelContext
    @Environment(Navigator.self) private var navigator
    @Query(filter: #Predicate<Todo> { $0.completedDate == nil }) private var openTodos: [Todo]
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    @State private var projectToDelete: Project?
    @State private var projectToComplete: Project?

    private var counts: [SmartList: Int] {
        Dictionary(grouping: openTodos) { SmartList.of($0) }.mapValues(\.count)
    }

    /// Open todos per project, from the todo query rather than `project.todos`.
    private var projectCounts: [UUID: Int] {
        Dictionary(grouping: openTodos.filter { !$0.isTrashed }.compactMap(\.project?.id)) { $0 }.mapValues(\.count)
    }

    var body: some View {
        let counts = counts
        let projectCounts = projectCounts
        // Completed projects are in the Logbook.
        let openProjects = projects.filter { !$0.isCompleted }
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                row(.inbox, count: counts[.inbox])
                Spacer().frame(height: 12)
                row(.today, count: counts[.today])
                row(.upcoming)
                row(.anytime)
                row(.someday)
                Spacer().frame(height: 12)
                row(.people)
                Spacer().frame(height: 12)
                row(.logbook)
                row(.trash)

                Spacer().frame(height: 20)
                sectionHeader
                ForEach(openProjects) { project in
                    projectRow(project, count: projectCounts[project.id])
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background.secondary)
        .alert(
            "Delete \"\(projectToDelete?.name ?? "")\"?",
            isPresented: Binding(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }),
            presenting: projectToDelete
        ) { project in
            Button("Delete", role: .destructive) { delete(project) }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text(project.deletionSummary)
        }
        .alert(
            "Complete \"\(projectToComplete?.name ?? "")\"?",
            isPresented: Binding(get: { projectToComplete != nil }, set: { if !$0 { projectToComplete = nil } }),
            presenting: projectToComplete
        ) { project in
            Button("Complete") { complete(project) }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            let remaining = openTodos(in: project).count
            Text("Its \(remaining) remaining \(remaining == 1 ? "to-do" : "to-dos") will be completed too.")
        }
    }

    // MARK: - Rows

    private func row(_ list: SmartList, count: Int? = nil) -> some View {
        rowButton(isSelected: selection == .smart(list), action: { selection = .smart(list) }) {
            Image(systemName: list.systemImage)
                .foregroundStyle(list.tint)
                .frame(width: 18)
            Text(list.title)
            Spacer()
            countLabel(count)
        }
    }

    private func projectRow(_ project: Project, count: Int?) -> some View {
        rowButton(isSelected: selection == .project(project.id), action: { selection = .project(project.id) }) {
            Image(systemName: project.icon)
                .foregroundStyle(.blue)
                .frame(width: 18)
            Text(project.name)
                .lineLimit(1)
            Spacer()
            countLabel(count)
        }
        .contextMenu {
            Button("Complete Project") { requestCompletion(of: project) }
            Divider()
            Button("Delete Project…", role: .destructive) { projectToDelete = project }
        }
    }

    private func rowButton<Label: View>(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) { label() }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isSelected ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func countLabel(_ count: Int?) -> some View {
        if let count, count > 0 {
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text("Projects")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button { createProject() } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("New Project")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Actions

    private func createProject() {
        // The name is checked against every project first: a duplicate would upsert over one.
        let project = Project(name: ProjectNaming.uniqueName(existing: projects.map(\.name)))
        project.sortOrder = (projects.map(\.sortOrder).max() ?? -1) + 1
        modelContext.insert(project)
        save()
        selection = .project(project.id)
        navigator.renamingProjectID = project.id
    }

    private func openTodos(in project: Project) -> [Todo] {
        openTodos.filter { !$0.isTrashed && $0.project?.id == project.id }
    }

    /// Completing a project completes its open todos too, so ask first when there are any.
    private func requestCompletion(of project: Project) {
        if openTodos(in: project).isEmpty {
            complete(project)
        } else {
            projectToComplete = project
        }
    }

    private func complete(_ project: Project) {
        ProjectCompletion.complete(project, openTodos: openTodos(in: project))
        save()
    }

    private func delete(_ project: Project) {
        if selection == .project(project.id) {
            selection = .smart(.today)
        }
        modelContext.delete(project)
        save()
    }

    private func save() {
        try? modelContext.save()
    }
}

extension SmartList {
    /// Icon colours, after Things.
    var tint: Color {
        switch self {
        case .inbox: .blue
        case .today: .yellow
        case .upcoming: .red
        case .anytime: .teal
        case .someday: .brown
        case .people: .purple
        case .logbook: .green
        case .trash: .gray
        }
    }
}
