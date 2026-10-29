import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData


struct Meetings: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage meetings",
        subcommands: [List.self, Add.self, Edit.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List meetings"
        )

        @Option(name: .long, help: "Start date (ISO 8601, e.g. 2026-04-28). Defaults to a week ago")
        var from: String?

        @Option(name: .long, help: "End date, inclusive (ISO 8601, e.g. 2026-05-02)")
        var to: String?

        @Option(name: .long, help: "Filter by attendee name")
        var person: String?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let container = try Store.makeContainer()
            let context = ModelContext(container)

            let range = try CLIDate.range(from: from, to: to, defaultFrom: CLIDate.weekAgo, defaultTo: .distantFuture)
            let start = range.lowerBound
            let end = range.upperBound

            let descriptor = FetchDescriptor<Meeting>(
                predicate: #Predicate { $0.date >= start && $0.date < end },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            var meetings = try context.fetch(descriptor)

            if let person {
                meetings = meetings.filter { m in
                    m.attendees.contains { $0.name.localizedCaseInsensitiveContains(person) }
                }
            }

            try printJSON(meetings.map(MeetingDTO.from), pretty: pretty)
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Make a meeting from a calendar event, as the event's Add Notes does"
        )

        @Option(name: .long, help: "Calendar event UUID, from events list")
        var event: String

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            guard let uuid = UUID(uuidString: event) else {
                throw ValidationError("Invalid UUID: \(event)")
            }
            let context = ModelContext(try Store.makeContainer())
            guard let calEvent = try context.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.id == uuid })).first else {
                throw ValidationError("Calendar event not found: \(event)")
            }
            if let meeting = calEvent.meeting {
                throw ValidationError("Event already has a meeting: \(meeting.id)")
            }
            if let interview = calEvent.interview {
                throw ValidationError("Event is an interview: \(interview.id)")
            }
            let meeting = calEvent.createMeeting(in: context)
            try context.save()

            try printJSON(MeetingDTO.from(meeting), pretty: pretty)
        }
    }

    struct Edit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Change a meeting's title, date, privacy, notes or Slack link",
            discussion: "An empty value clears a field, as emptying it in the app does. Pass - to read one value from stdin."
        )

        @Argument(help: "Meeting UUID")
        var id: String

        @Option(name: .long, help: "New title")
        var title: String?

        @Option(name: .long, help: "Date as YYYY-MM-DDTHH:MM (local), or YYYY-MM-DD to keep the time")
        var date: String?

        @Flag(name: .customLong("private"), inversion: .prefixedNo, help: "Make it private, or not, as the app's lock does")
        var isPrivate: Bool?

        @Option(name: .long, help: "Prep notes (markdown)")
        var prepNotes: String?

        @Option(name: .long, help: "Notes (markdown)")
        var notes: String?

        @Option(name: .long, help: "Summary (markdown)")
        var summary: String?

        @Option(name: .long, help: "Transcript")
        var transcript: String?

        @Option(name: .long, help: "Link to where the notes were shared")
        var slackURL: String?

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError("Title can't be empty")
            }
            if let slackURL, !slackURL.isEmpty {
                guard let url = URL(string: slackURL), ["http", "https"].contains(url.scheme?.lowercased()) else {
                    throw ValidationError("Invalid URL: \(slackURL)")
                }
            }
            let changes: [Bool] = [title != nil, date != nil, isPrivate != nil, prepNotes != nil, notes != nil, summary != nil, transcript != nil, slackURL != nil]
            if !changes.contains(true) {
                throw ValidationError("Nothing to change")
            }
        }

        mutating func run() async throws {
            let texts = try TextInput.resolve([prepNotes, notes, summary, transcript])
            let context = ModelContext(try Store.makeContainer())
            let meeting = try Meetings.meeting(id: id, in: context)

            if let title { meeting.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let date { meeting.date = try CLIDate.dateTime(date, keepingTimeOf: meeting.date) }
            if let isPrivate { meeting.isPrivate = isPrivate }
            if let text = texts[0] { meeting.prepNotes = TextInput.field(text) }
            if let text = texts[1] { meeting.notes = TextInput.field(text) }
            if let text = texts[2] { meeting.summary = TextInput.field(text) }
            if let text = texts[3] { meeting.transcript = TextInput.field(text) }
            if let slackURL {
                meeting.slackURL = slackURL.isEmpty ? nil : URL(string: slackURL)
            }
            try context.save()

            try printJSON(MeetingDTO.from(meeting), pretty: pretty)
        }
    }

    static func meeting(id: String, in context: ModelContext) throws -> Meeting {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("Invalid UUID: \(id)")
        }
        guard let meeting = try context.fetch(FetchDescriptor<Meeting>(predicate: #Predicate { $0.id == uuid })).first else {
            throw ValidationError("Meeting not found: \(id)")
        }
        return meeting
    }
}
