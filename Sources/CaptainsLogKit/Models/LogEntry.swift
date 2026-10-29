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
