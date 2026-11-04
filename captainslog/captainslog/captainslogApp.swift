import SwiftUI
import SwiftData
import CaptainsLogKit

@main
struct CaptainsLogApp: App {
    private var container: ModelContainer = {
        do {
            return try Store.makeContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var settings = AppSettings()
    @State private var syncCoordinator: SyncCoordinator
    @State private var quickEntry: QuickEntryController

    init() {
        let container = self.container
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _syncCoordinator = State(initialValue: SyncCoordinator(container: container, settings: settings))
        _quickEntry = State(initialValue: QuickEntryController(container: container, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    guard !Store.isScratch else { return }
                    syncCoordinator.startPeriodicSync()
                }
        }
        .modelContainer(container)
        .environment(settings)
        .environment(syncCoordinator)
        .commands { AboutCommands() }

        Window("About Captain's Log", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .modelContainer(container)
                .environment(settings)
                .environment(syncCoordinator)
        }

        MenuBarExtra("Captain's Log", image: "MenuBarIcon") {
            MenuBarView()
                .modelContainer(container)
                .environment(settings)
                .environment(syncCoordinator)
        }
        .menuBarExtraStyle(.window)
    }
}
