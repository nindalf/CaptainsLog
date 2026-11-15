import AppKit
import SwiftUI
import SwiftData
import CaptainsLogKit

/// What a view can do now for each command it handles. Views publish these as focused values; the
/// menus and the palette merge them over `CommandRunner`'s app-wide ones. A command with no
/// handler is disabled.
struct CommandHandlers {
    private var actions: [AppCommand: () -> Void] = [:]

    subscript(command: AppCommand) -> (() -> Void)? {
        get { actions[command] }
        set { actions[command] = newValue }
    }

    /// `self` wins where both handle a command.
    func merging(_ other: CommandHandlers?) -> CommandHandlers {
        guard let other else { return self }
        var merged = self
        merged.actions.merge(other.actions) { mine, _ in mine }
        return merged
    }

    /// AppKit offers a key to the menu before the text view sees it, so a Cmd-Delete typed in text
    /// would delete the record. Typed in editable text, it deletes to the start of the line instead.
    func perform(_ command: AppCommand, typed: Bool = false) {
        if typed, command == .delete, let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable {
            text.deleteToBeginningOfLine(nil)
        } else if let action = actions[command] {
            action()
        } else {
            NSSound.beep()
        }
    }
}

extension FocusedValues {
    /// A list's: its selection, or its open card. Published by `selectionCommands(_:claimsOnAppear:selection:focus:)`.
    @Entry var selectionCommands: CommandHandlers?
    /// The top detail page's: meeting, interview, person. Published by `pageCommands(_:)`.
    @Entry var pageCommands: CommandHandlers?
    /// The tab's own, used only at the root of its stack: a pushed page keeps the tab under it.
    @Entry var tabCommands: CommandHandlers?
    @Entry var commandRunner: CommandRunner?
}

extension View {
    /// Publishes a list's selection commands while it's the list they act on: the one last selected
    /// in, or shown with `claimsOnAppear` (docs/overview.md says why not by focus). `focus` puts
    /// focus back in the list once the palette closes.
    func selectionCommands(
        _ handlers: CommandHandlers, claimsOnAppear: Bool, selection: some Equatable, focus: @escaping () -> Void
    ) -> some View {
        modifier(SelectionCommandsModifier(handlers: handlers, claimsOnAppear: claimsOnAppear, selection: selection, focus: focus))
    }
}

extension View {
    /// Publishes a detail page's commands while it's the top of the stack: a page pushed from it
    /// keeps it alive underneath.
    func pageCommands(_ handlers: CommandHandlers) -> some View {
        modifier(PageCommandsModifier(handlers: handlers))
    }
}

private struct PageCommandsModifier: ViewModifier {
    let handlers: CommandHandlers

    @Environment(Navigator.self) private var navigator
    @State private var depth: Int?

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.pageCommands, navigator.path.count == depth ? handlers : nil)
            .onAppear { depth = navigator.path.count }
    }
}

private struct SelectionCommandsModifier<Selection: Equatable>: ViewModifier {
    let handlers: CommandHandlers
    let claimsOnAppear: Bool
    let selection: Selection
    let focus: () -> Void

    @Environment(Navigator.self) private var navigator
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.selectionCommands, navigator.commandListID == id ? handlers : nil)
            .onAppear { if claimsOnAppear { navigator.commandListID = id } }
            .onChange(of: selection) { navigator.commandListID = id }
            .onChange(of: navigator.paletteReturnTick) { if navigator.commandListID == id { focus() } }
    }
}

/// The app-wide commands, and the window's state they act on. `ContentView` publishes one.
struct CommandRunner {
    let navigator: Navigator
    let settings: AppSettings
    let syncCoordinator: SyncCoordinator
    let quickEntry: QuickEntryController?
    let modelContext: ModelContext
    let openSettings: OpenSettingsAction

    /// The handlers in force, most specific first: the list commands act on, the open page, the
    /// tab, then the app's. A pushed page hides its tab's lists and the tab's own commands, which
    /// stay alive underneath it. While the palette is open, only its own commands work, so a key
    /// can't act on the list behind it.
    func handlers(selection: CommandHandlers?, page: CommandHandlers?, tab: CommandHandlers?) -> CommandHandlers {
        let local = navigator.path.isEmpty ? (selection ?? CommandHandlers()).merging(tab) : page ?? CommandHandlers()
        // The palette takes focus from the list, so it keeps the handlers in force when it opened.
        // Switching modes while it's open keeps them, and where focus goes back to.
        let snapshot = local.merging(global)
        var all = navigator.palette == nil ? snapshot : CommandHandlers()
        let navigator = navigator
        let present = { (mode: PaletteRequest.Mode) in
            var request = PaletteRequest(mode: mode, handlers: snapshot)
            if let open = navigator.palette {
                switch open.mode {
                case .commands, .search: request.handlers = open.handlers
                case .project, .meetings: break
                }
                request.returnFocus = open.returnFocus
            }
            navigator.palette = request
        }
        let kind = tabSearchKind
        all[.palette] = { present(.commands) }
        all[.findInTab] = (navigator.palette == nil ? local[.findInTab] : nil) ?? { present(.search(kind)) }
        all[.findEverywhere] = { present(.search(nil)) }
        return all
    }

    private var global: CommandHandlers {
        var handlers = CommandHandlers()
        let navigator = navigator
        handlers[.newLogEntry] = { [quickEntry] in quickEntry?.show(.log) }
        handlers[.newTodo] = { [quickEntry] in quickEntry?.show(.todo) }
        for item in settings.visibleSidebarItems {
            handlers[.goTo(item)] = { navigator.select(item) }
        }
        for list in SmartList.allCases {
            handlers[.todoList(list)] = {
                navigator.todoSelection = .smart(list)
                navigator.select(.todos)
            }
        }
        if !navigator.path.isEmpty {
            handlers[.back] = { navigator.path.removeLast() }
        }
        handlers[.toggleSidebar] = {
            NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        }
        handlers[.settings] = { [openSettings] in openSettings() }
        if !syncCoordinator.isSyncing {
            handlers[.sync] = { [syncCoordinator] in
                if !syncCoordinator.isSyncing { syncCoordinator.syncNow() }
            }
        }
        // The palette looks the meetings up when it opens, since the selected one moves with the time.
        handlers[.join] = { navigator.palette = PaletteRequest(mode: .meetings(.join)) }
        handlers[.openMeeting] = { navigator.palette = PaletteRequest(mode: .meetings(.notes)) }
        return handlers
    }

    /// What Find in This Tab searches: the kind the tab lists, or everything.
    private var tabSearchKind: SearchKind? {
        switch navigator.selectedItem {
        case .log: .log
        case .meetings: .meeting
        case .pullRequests: .pr
        case .todos: .todo
        case .interviews: .interview
        case .people: .person
        case .dashboard, .search, nil: nil
        }
    }
}

/// An open palette: what it lists, and the commands it can run.
struct PaletteRequest {
    enum Mode: Hashable {
        case commands
        /// Records of one kind, or of every kind.
        case search(SearchKind?)
        /// A project for `chooseProject`, or none.
        case project
        /// One of today's meetings, to join or to open.
        case meetings(TodaysMeetings.Purpose)
    }

    var mode: Mode
    var handlers = CommandHandlers()
    var chooseProject: ((Project?) -> Void)?
    /// What had focus when it opened, to hand focus back to on closing.
    weak var returnFocus: NSResponder? = NSApp.keyWindow?.firstResponder
}

extension TodaysMeetings {
    init(in context: ModelContext, for purpose: Purpose, now: Date = .now) {
        let startOfToday = Calendar.current.startOfDay(for: now)
        let events = (try? context.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.endTime > startOfToday }))) ?? []
        self.init(among: events, for: purpose, now: now)
    }
}
