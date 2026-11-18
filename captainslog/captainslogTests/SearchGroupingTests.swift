import Testing
import CaptainsLogKit
@testable import Captain_s_Log

/// Search shows its results grouped by kind, and arrow keys walk them in that order.
struct SearchGroupingTests {
    @Test func groupsFollowTheirFirstResultAndKeepTheOrderWithin() {
        let results: [(String, SearchKind)] = [
            ("newest log", .log), ("a meeting", .meeting), ("older log", .log), ("a todo", .todo), ("oldest log", .log),
        ]
        let groups = SearchKind.group(results) { $0.1 }

        #expect(groups.map(\.kind) == [.log, .meeting, .todo])
        #expect(groups[0].items.map(\.0) == ["newest log", "older log", "oldest log"])
    }
}
