import SwiftUI
import CaptainsLogKit

struct LogListView: View {
    @State private var typeFilter: FeedItemType?
    @State private var addTick = 0

    var body: some View {
        LogListContent(typeFilter: $typeFilter, addTick: addTick)
            .navigationTitle("Log")
            .toolbar { toolbarContent }
            .focusedSceneValue(\.tabCommands, tabCommands)
    }

    private var tabCommands: CommandHandlers {
        var handlers = CommandHandlers()
        handlers[.newLogEntry] = { addTick += 1 }
        return handlers
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            ToolbarFilter(selection: $typeFilter, kinds: FeedItemType.allCases, title: \.rawValue, icon: \.icon)
        }
        ToolbarItem {
            Button { addTick += 1 } label: {
                Label("Add Entry", systemImage: "plus")
            }
            .help(AppCommand.newLogEntry.help("Add Entry"))
        }
    }
}

#Preview {
    NavigationStack {
        LogListView()
    }
    .previewEnvironment()
}
