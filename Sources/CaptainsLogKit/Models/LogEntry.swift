import Foundation
import SwiftData

@Model
public final class LogEntry {
    public var id: UUID = UUID()
    public var timestamp: Date
    public var source: EntrySource
    public var isPrivate: Bool = false
    public var title: String
    public var content: String
    public var people: [Person] = []
    public var project: Project?
    public var tags: [String] = []
    public var externalURL: URL?

    #Index<LogEntry>([\.timestamp])

    public var externalID: String?

    public init(
        timestamp: Date,
        source: EntrySource,
        title: String,
        content: String,
        isPrivate: Bool = false
    ) {
        self.timestamp = timestamp
        self.source = source
        self.title = title
        self.content = content
        self.isPrivate = isPrivate
    }
}

extension LogEntry {
    /// Moves the entry to another day at the same time of day: the day is what's picked, and the
    /// time keeps its order among that day's entries.
    public func move(toDay day: Date, calendar: Calendar = .current) {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: timestamp), to: calendar.startOfDay(for: day)).day ?? 0
        timestamp = calendar.date(byAdding: .day, value: days, to: timestamp) ?? timestamp
    }
}
