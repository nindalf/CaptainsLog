import SwiftUI
import SwiftData
import CaptainsLogKit

nonisolated enum TodoFocusField: Hashable {
    case list
    case title(UUID)
    case notes(UUID)
}

struct TodoListView: View {
    @Environment(Navigator.self) private var navigator
    @Query private var projects: [Project]
    @State private var addTick = 0

    private var selection: TodoSelection { navigator.todoSelection }

    private var selectedProject: Project? {
        guard let id = selection.projectID else { return nil }
        return projects.first { $0.id == id }
    }

    private var title: String {
        if let list = selection.smartList { return list.title }
        return selectedProject?.name ?? "Project"
    }

    var body: some View {
        @Bindable var navigator = navigator
        HStack(spacing: 0) {
            SmartListColumn(selection: $navigator.todoSelection)
                .frame(width: 200)
            Divider()
            VStack(spacing: 0) {
                if let selectedProject {
                    ProjectHeader(project: selectedProject)
                }
                TodoListContent(scope: selection, addTick: addTick)
            }
        }
        .navigationTitle(title)
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button { addTick += 1 } label: {
                Label("Add Todo", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!selection.acceptsTodos)
        }
    }
}

#Preview {
    NavigationStack {
        TodoListView()
    }
    .previewEnvironment()
}
