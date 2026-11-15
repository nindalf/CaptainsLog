import Testing
@testable import Captain_s_Log

// The command list behind the menus and the palette.
struct AppCommandTests {
    /// Settings overrides will key on the id, and a key means one thing (issue #66).
    @Test func idsAndKeysAreUnique() {
        let commands = AppCommand.all()
        #expect(Set(commands.map(\.id)).count == commands.count)
        let keys = commands.compactMap { $0.shortcut(visibleTabs: SidebarItem.allCases) }
        #expect(Set(keys.map(\.label)).count == keys.count)
    }

    /// Tabs take Cmd-1 to Cmd-8 in the sidebar's visible order, so a hidden tab shifts the rest up.
    @Test func tabKeysFollowTheVisibleOrder() {
        let tabs: [SidebarItem] = [.todos, .dashboard, .log]
        #expect(AppCommand.goTo(.todos).shortcut(visibleTabs: tabs)?.label == "⌘1")
        #expect(AppCommand.goTo(.log).shortcut(visibleTabs: tabs)?.label == "⌘3")
        #expect(AppCommand.goTo(.people).shortcut(visibleTabs: tabs) == nil)
    }
}
