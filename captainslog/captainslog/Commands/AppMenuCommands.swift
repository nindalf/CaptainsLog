import AppKit
import SwiftUI
import CaptainsLogKit

/// The menu bar's commands, from `AppCommand`. A menu key works from any tab, whatever has focus:
/// the menu reads the key window's focused values rather than waiting for a view to see the key.
struct AppMenuCommands: Commands {
    let settings: AppSettings

    @FocusedValue(\.commandRunner) private var runner
    @FocusedValue(\.selectionCommands) private var selection
    @FocusedValue(\.pageCommands) private var page
    @FocusedValue(\.tabCommands) private var tab

    var body: some Commands {
        let handlers = runner?.handlers(selection: selection, page: page, tab: tab) ?? CommandHandlers()
        // Replaces New Window: the app has one.
        CommandGroup(replacing: .newItem) {
            item(.newLogEntry, handlers)
            item(.newTodo, handlers)
            item(.newProject, handlers)
            Divider()
            item(.delete, handlers)
        }
        CommandGroup(before: .textEditing) {
            item(.findInTab, handlers)
            item(.findEverywhere, handlers)
            Divider()
        }
        CommandGroup(before: .sidebar) {
            item(.palette, handlers)
            item(.sync, handlers)
            Divider()
        }
        SidebarCommands()
        CommandMenu("Go") {
            ForEach(settings.visibleSidebarItems) { item(.goTo($0), handlers) }
            Divider()
            Menu("Todo Lists") {
                ForEach(SmartList.allCases, id: \.self) { item(.todoList($0), handlers) }
            }
            Divider()
            item(.back, handlers)
            item(.join, handlers)
        }
        CommandMenu("Todo") {
            item(.complete, handlers)
            Divider()
            item(.today, handlers)
            item(.someday, handlers)
            item(.when, handlers)
            item(.dayLater, handlers)
            item(.dayEarlier, handlers)
            Divider()
            item(.moveToProject, handlers)
        }
    }

    /// Delete stays enabled, so a Cmd-Delete typed in text reaches `perform`, which hands it to the
    /// text: a disabled menu key would swallow it with a beep.
    private func item(_ command: AppCommand, _ handlers: CommandHandlers) -> some View {
        Button(command.menuTitle) { handlers.perform(command, typed: NSApp.currentEvent?.type == .keyDown) }
            .keyboardShortcut(command.shortcut(visibleTabs: settings.visibleSidebarItems))
            .disabled(command != .delete && handlers[command] == nil)
    }
}
