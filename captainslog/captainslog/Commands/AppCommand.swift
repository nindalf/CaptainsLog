import SwiftUI
import CaptainsLogKit

/// Every command the menus and the palette offer, defined once. `id` is stable: overrides in
/// Settings (#70) will key on it, so never rename one.
enum AppCommand: Hashable, Identifiable {
    case palette, findInTab, findEverywhere
    case newLogEntry, newTodo, newProject
    case goTo(SidebarItem), todoList(SmartList), back, toggleSidebar, settings
    case sync, join, delete
    case complete, today, someday, when, dayLater, dayEarlier, moveToProject
    // Palette only.
    case openInGitHub, addFeedback, mergePerson, importRoster, exportRoster, emptyTrash

    var id: String {
        switch self {
        case .palette: "palette"
        case .findInTab: "findInTab"
        case .findEverywhere: "findEverywhere"
        case .newLogEntry: "newLogEntry"
        case .newTodo: "newTodo"
        case .newProject: "newProject"
        case .goTo(let item): "goTo.\(item.rawValue)"
        case .todoList(let list): "todoList.\(list.rawValue)"
        case .back: "back"
        case .toggleSidebar: "toggleSidebar"
        case .settings: "settings"
        case .sync: "sync"
        case .join: "join"
        case .delete: "delete"
        case .complete: "complete"
        case .today: "today"
        case .someday: "someday"
        case .when: "when"
        case .dayLater: "dayLater"
        case .dayEarlier: "dayEarlier"
        case .moveToProject: "moveToProject"
        case .openInGitHub: "openInGitHub"
        case .addFeedback: "addFeedback"
        case .mergePerson: "mergePerson"
        case .importRoster: "importRoster"
        case .exportRoster: "exportRoster"
        case .emptyTrash: "emptyTrash"
        }
    }

    /// The palette's name, which says what it does out of context.
    var title: String {
        switch self {
        case .palette: "Command Palette"
        case .findInTab: "Find in This Tab"
        case .findEverywhere: "Find Everywhere…"
        case .newLogEntry: "New Log Entry"
        case .newTodo: "New Todo"
        case .newProject: "New Project"
        case .goTo(let item): "Go to \(item.label)"
        case .todoList(let list): "Todos: \(list.title.capitalized)"
        case .back: "Back"
        case .toggleSidebar: "Show or Hide Sidebar"
        case .settings: "Settings"
        case .sync: "Sync Now"
        case .join: "Join Meeting"
        case .delete: "Delete"
        case .complete: "Complete Todo"
        case .today: "Schedule for Today"
        case .someday: "Move to Someday"
        case .when: "When…"
        case .dayLater: "One Day Later"
        case .dayEarlier: "One Day Earlier"
        case .moveToProject: "Move to Project…"
        case .openInGitHub: "Open in GitHub"
        case .addFeedback: "Add Feedback"
        case .mergePerson: "Merge Person…"
        case .importRoster: "Import Roster…"
        case .exportRoster: "Export Roster…"
        case .emptyTrash: "Empty Trash…"
        }
    }

    /// The menu's name, where the menu gives the context.
    var menuTitle: String {
        switch self {
        case .goTo(let item): item.label
        case .todoList(let list): list.title
        case .palette: "Command Palette…"
        case .findInTab: "Find…"
        case .complete: "Complete"
        case .today: "Today"
        case .someday: "Someday"
        default: title
        }
    }

    var systemImage: String {
        switch self {
        case .palette: "command"
        case .findInTab, .findEverywhere: "magnifyingglass"
        case .newLogEntry: "book"
        case .newTodo: "checklist"
        case .newProject: "list.bullet"
        case .goTo(let item): item.icon
        case .todoList(let list): list.systemImage
        case .back: "chevron.left"
        case .toggleSidebar: "sidebar.left"
        case .settings: "gear"
        case .sync: "arrow.clockwise"
        case .join: "video"
        case .delete: "trash"
        case .complete: "checkmark.square"
        case .today: "star"
        case .someday: SmartList.someday.systemImage
        case .when: "calendar"
        case .dayLater: "arrow.right"
        case .dayEarlier: "arrow.left"
        case .moveToProject: "arrow.right.square"
        case .openInGitHub: "arrow.up.right.square"
        case .addFeedback: "text.bubble"
        case .mergePerson: "arrow.triangle.merge"
        case .importRoster: "square.and.arrow.down"
        case .exportRoster: "square.and.arrow.up"
        case .emptyTrash: "trash.slash"
        }
    }

    /// The default key. Tabs are numbered in the sidebar's visible order, so theirs depends on it.
    func shortcut(visibleTabs: [SidebarItem]) -> KeyboardShortcut? {
        switch self {
        case .palette: KeyboardShortcut("p", modifiers: [.command, .shift])
        case .findInTab: KeyboardShortcut("f", modifiers: .command)
        case .findEverywhere: KeyboardShortcut("f", modifiers: [.command, .shift])
        case .newLogEntry: KeyboardShortcut("l", modifiers: .command)
        case .newTodo: KeyboardShortcut("t", modifiers: .command)
        case .newProject: KeyboardShortcut("n", modifiers: [.command, .option])
        case .goTo(let item):
            visibleTabs.firstIndex(of: item).flatMap { Self.digit($0) }.map { KeyboardShortcut($0, modifiers: .command) }
        case .todoList(let list):
            SmartList.allCases.firstIndex(of: list).flatMap { Self.digit($0) }.map { KeyboardShortcut($0, modifiers: [.command, .option]) }
        case .back: KeyboardShortcut("[", modifiers: .command)
        case .toggleSidebar: KeyboardShortcut("s", modifiers: [.command, .control])
        case .settings: KeyboardShortcut(",", modifiers: .command)
        case .sync: KeyboardShortcut("r", modifiers: .command)
        case .join: KeyboardShortcut("j", modifiers: .command)
        case .delete: KeyboardShortcut(.delete, modifiers: .command)
        case .complete: KeyboardShortcut("k", modifiers: .command)
        case .today: KeyboardShortcut("t", modifiers: [.command, .shift])
        case .someday: KeyboardShortcut("o", modifiers: .command)
        case .when: KeyboardShortcut("s", modifiers: .command)
        case .dayLater: KeyboardShortcut("]", modifiers: .control)
        case .dayEarlier: KeyboardShortcut("[", modifiers: .control)
        case .moveToProject: KeyboardShortcut("m", modifiers: [.command, .shift])
        case .openInGitHub, .addFeedback, .mergePerson, .importRoster, .exportRoster, .emptyTrash: nil
        }
    }

    /// "Title (⌘T)", for a button's help.
    func help(_ title: String) -> String {
        shortcut(visibleTabs: []).map { "\(title) (\($0.label))" } ?? title
    }

    /// 1 to 9 for the first nine positions.
    private static func digit(_ index: Int) -> KeyEquivalent? {
        index < 9 ? KeyEquivalent(Character(String(index + 1))) : nil
    }

    /// Every command, in the palette's order, with the tabs in the sidebar's.
    static func all(tabs: [SidebarItem] = SidebarItem.allCases) -> [AppCommand] {
        [.newLogEntry, .newTodo, .newProject]
            + [.complete, .today, .someday, .when, .dayLater, .dayEarlier, .moveToProject, .delete]
            + [.join, .openInGitHub, .addFeedback, .mergePerson, .importRoster, .exportRoster, .emptyTrash]
            + tabs.map(AppCommand.goTo) + SmartList.allCases.map(AppCommand.todoList)
            + [.back, .findInTab, .findEverywhere, .sync, .toggleSidebar, .settings]
    }
}

extension KeyboardShortcut {
    /// As menus show it: modifiers in the system's order, then the key.
    var label: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        text += key == .delete ? "⌫" : String(key.character).uppercased()
        return text
    }
}
