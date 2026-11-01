import AppKit
import SwiftUI
import SwiftData
import CaptainsLogKit

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @State private var navigator = Navigator()

    // Routed through Navigator.select so a user-driven tab change clears the previous tab's stack.
    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { navigator.selectedItem },
            set: { navigator.select($0) }
        )
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: selection)
        } detail: {
            NavigationStack(path: $navigator.path) {
                tab
                    // Registered once for every tab, so any tab can push these and Navigator can open them.
                    .navigationDestination(for: Meeting.self) { meeting in
                        MeetingDetailView(meeting: meeting)
                    }
                    .navigationDestination(for: Interview.self) { interview in
                        InterviewDetailView(interview: interview)
                    }
                    .navigationDestination(for: Person.self) { person in
                        PersonDetailView(person: person)
                    }
            }
            .id(navigator.selectedItem)
        }
        .environment(navigator)
        // A setup step finished in Terminal shows as soon as the app comes back.
        .task { await syncCoordinator.refreshSetup() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await syncCoordinator.refreshSetup() }
        }
        .onAppear {
            // Open on the sidebar's first tab when the Dashboard is hidden.
            if let item = navigator.selectedItem, !settings.isShown(item) {
                navigator.select(settings.visibleSidebarItems.first)
            }
        }
    }

    @ViewBuilder
    private var tab: some View {
        switch navigator.selectedItem {
        case .dashboard:
            DashboardView(selectedSidebarItem: selection)
        case .log:
            LogListView()
        case .meetings:
            MeetingListView()
        case .pullRequests:
            PRListView()
        case .todos:
            TodoListView()
        case .interviews:
            InterviewListView()
        case .people:
            PeopleListView()
        case .search:
            SearchView()
        case nil:
            Text("Select an item")
        }
    }
}
