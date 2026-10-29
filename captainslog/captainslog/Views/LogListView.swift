import SwiftUI
import CaptainsLogKit

struct LogListView: View {
    @State private var typeFilter: FeedItemType?
    @State private var addTick = 0

    var body: some View {
        LogListContent(typeFilter: $typeFilter, addTick: addTick)
            .navigationTitle("Log")
            .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Picker("Type", selection: $typeFilter) {
                Text("All").tag(FeedItemType?.none)
                ForEach(FeedItemType.allCases) { type in
                    Label(type.rawValue, systemImage: type.icon)
                        .tag(FeedItemType?.some(type))
                }
            }
        }
        ToolbarItem {
            Button { addTick += 1 } label: {
                Label("Add Entry", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

#Preview {
    NavigationStack {
        LogListView()
    }
    .previewEnvironment()
}
