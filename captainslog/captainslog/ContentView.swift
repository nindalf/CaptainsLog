import AppKit
import SwiftUI
import SwiftData
import CaptainsLogKit

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.quickEntry) private var quickEntry
    @Environment(\.openSettings) private var openSettings
    @State private var navigator = Navigator()

    private var commandRunner: CommandRunner {
        CommandRunner(
            navigator: navigator,
            settings: settings,
            syncCoordinator: syncCoordinator,
            quickEntry: quickEntry,
            modelContext: modelContext,
            openSettings: openSettings
        )
    }

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
        .overlay(alignment: .top) { palette }
        .environment(navigator)
        .focusedSceneValue(\.commandRunner, commandRunner)
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
    private var palette: some View {
        if let request = navigator.palette {
            ZStack(alignment: .top) {
                // A click outside closes it.
                Color.black.opacity(0.001)
                    .onTapGesture { closePalette(then: nil) }
                CommandPalette(request: request, onClose: closePalette)
                    .padding(.top, 48)
                    .id(request.mode)
            }
        }
    }

    /// Once the palette has gone, hands focus back to the text it was in, else to the list commands
    /// act on, then runs what was chosen.
    private func closePalette(then action: (() -> Void)?) {
        let responder = navigator.palette?.returnFocus
        navigator.palette = nil
        DispatchQueue.main.async {
            // A text field's first responder is the window's shared field editor; refocus the field.
            let target = (responder as? NSTextView).flatMap { $0.isFieldEditor ? $0.delegate as? NSResponder : nil } ?? responder
            let backInText = (target as? NSView).map { view in
                (view is NSTextField || view is NSTextView) && view.window?.makeFirstResponder(view) == true
            } ?? false
            if !backInText { navigator.paletteReturnTick += 1 }
            action?()
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
            CalendarTabView()
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
