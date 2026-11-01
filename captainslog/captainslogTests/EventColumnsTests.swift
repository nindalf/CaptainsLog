import Foundation
import Testing
@testable import Captain_s_Log

struct EventColumnsTests {
    private func at(_ time: String) -> Date {
        let parts = time.split(separator: ":").map { Int($0)! }
        return Date(timeIntervalSinceReferenceDate: TimeInterval(parts[0] * 3600 + parts[1] * 60))
    }

    private func layout(_ events: [(String, String)]) -> [EventColumns.Slot] {
        EventColumns.layout(events.map { (at($0.0), at($0.1)) })
    }

    @Test func longEventDoesNotGiveEveryEventItsOwnColumn() {
        let slots = layout([
            ("09:00", "10:00"), // commute
            ("09:45", "10:15"), // standup
            ("10:00", "15:00"), // hackathon
            ("10:15", "10:45"), // daily
            ("11:15", "12:00"), // show and tell
            ("13:30", "14:00"), // workshop
            ("14:30", "15:00"), // 1:1
            ("15:00", "16:00"), // presentation
            ("15:00", "15:30"), // 1:1
            ("16:00", "17:00"), // all hands
        ])
        #expect(slots[0] == .init(column: 0, span: 1, columns: 2))
        #expect(slots[1] == .init(column: 1, span: 1, columns: 2))
        #expect(slots[2] == .init(column: 0, span: 1, columns: 2))
        #expect(slots[3...6].allSatisfy { $0 == .init(column: 1, span: 1, columns: 2) })
        #expect(slots[7] == .init(column: 0, span: 1, columns: 2))
        #expect(slots[8] == .init(column: 1, span: 1, columns: 2))
        #expect(slots[9] == .init(column: 0, span: 1, columns: 1))
    }

    @Test func eventStretchesAcrossColumnsFreeForItsWholeSpan() {
        let slots = layout([
            ("09:00", "12:00"),
            ("09:00", "10:00"),
            ("09:00", "10:00"),
            ("10:30", "11:30"),
        ])
        #expect(slots[3] == .init(column: 1, span: 2, columns: 3))
    }

    @Test func zeroLengthEventsLayOutAsTheyDraw() {
        let slots = layout([("09:00", "09:00"), ("09:05", "09:30")])
        #expect(slots.map(\.columns) == [2, 2])
    }
}
