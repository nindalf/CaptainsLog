import Foundation
import SwiftData

@Model
public final class Feedback {
    public var id: UUID = UUID()
    public var date: Date
    public var person: Person
    public var content: String
    /// Hidden from the CLI apart from its date, as other private records are. From schema V7.
    public var isPrivate: Bool = false

    public init(
        date: Date,
        person: Person,
        content: String
    ) {
        self.date = date
        self.person = person
        self.content = content
    }
}
