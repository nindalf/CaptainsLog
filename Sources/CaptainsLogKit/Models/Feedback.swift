import Foundation
import SwiftData

@Model
public final class Feedback {
    public var id: UUID = UUID()
    public var date: Date
    public var person: Person
    public var content: String

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
