import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

struct Events: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage calendar events",
        subcommands: [List.self, Hide.self, Unhide.self, Delete.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List calendar events in time order, leaving out ones hidden in the app"
        )

        @Option(name: .long, help: "Start date (ISO 8601, e.g. 2026-04-28). Defaults to today")
        var from: String?

        @Option(name: .long, help: "End date, inclusive (ISO 8601, e.g. 2026-05-02). Defaults to a week from --from")
        var to: String?

        @Flag(name: .long, help: "Include hidden events")
        var hidden: Bool = false

        @Flag(name: .long, help: "Only events that haven't started yet")
        var upcoming: Bool = false

        @Flag(name: .long, help: "Only meetings: leave out all-day events, interviews, and events without at least one other attendee")
        var meetings: Bool = false

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let defaultFrom = try from.map(CLIDate.day) ?? Calendar.current.startOfDay(for: .now)
            let range = try CLIDate.range(
                from: from, to: to, defaultFrom: defaultFrom,
                defaultTo: Calendar.current.date(byAdding: .day, value: 7, to: defaultFrom)!
            )
            let start = range.lowerBound
            let end = range.upperBound
            let includeHidden = hidden

            // Overlap rather than start time, so an all-day or multi-day event that began earlier still shows.
            let context = ModelContext(try Store.makeContainer())
            let descriptor = FetchDescriptor<CalendarEvent>(
                predicate: #Predicate { $0.startTime < end && $0.endTime > start && (includeHidden || !$0.isHidden) },
                sortBy: [SortDescriptor(\.startTime)]
            )
            var events = try context.fetch(descriptor)
            if upcoming {
                let now = Date.now
                events = events.filter { $0.startTime > now }
            }
            if meetings {
                events = events.filter { !$0.isAllDay && $0.interview == nil && $0.attendees.count >= 2 }
            }
            try printJSON(events.map(CalendarEventDTO.from), pretty: pretty)
        }
    }

    struct Hide: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Hide an event from the calendar, as its Hide action does. Sync won't bring it back"
        )

        @Argument(help: "Calendar event UUID")
        var id: String

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let event = try Events.event(id: id, in: context)
            event.isHidden = true
            try context.save()
            try printJSON(CalendarEventDTO.from(event), pretty: pretty)
        }
    }

    struct Unhide: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show a hidden event in the calendar again"
        )

        @Argument(help: "Calendar event UUID")
        var id: String

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let event = try Events.event(id: id, in: context)
            event.isHidden = false
            try context.save()
            try printJSON(CalendarEventDTO.from(event), pretty: pretty)
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete an event for good, with its meeting or interview if nothing was written in it",
            discussion: "A meeting or interview with notes is kept, unlinked. The next calendar sync can bring the event back; hide stops that."
        )

        @Argument(help: "Calendar event UUID")
        var id: String

        @Flag(name: .long, help: "Required: confirms the delete is permanent")
        var permanently: Bool = false

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        func validate() throws {
            guard permanently else {
                throw ValidationError("Deleting is permanent; pass --permanently to confirm")
            }
        }

        mutating func run() async throws {
            let context = ModelContext(try Store.makeContainer())
            let event = try Events.event(id: id, in: context)
            let dto = CalendarEventDTO.from(event)
            event.deleteWithEmptyStubs(in: context)
            try context.save()
            try printJSON(["deleted": [dto]], pretty: pretty)
        }
    }

    static func event(id: String, in context: ModelContext) throws -> CalendarEvent {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("Invalid UUID: \(id)")
        }
        guard let event = try context.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.id == uuid })).first else {
            throw ValidationError("Calendar event not found: \(id)")
        }
        return event
    }
}
