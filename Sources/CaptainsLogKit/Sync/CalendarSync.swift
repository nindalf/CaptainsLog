import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "sync.calendar")

private let gwsPath = "/opt/homebrew/bin/gws"

// MARK: - Agenda DTOs (all-day events)

private struct GWSAgendaResponse: Decodable {
    let count: Int
    let events: [GWSAgendaEvent]
}

private struct GWSAgendaEvent: Decodable {
    let calendar: String
    let start: String
    let end: String
    let summary: String
    let location: String?
}

// MARK: - Google Calendar API DTOs (detailed events)

private struct GCalListResponse: Decodable {
    let items: [GCalEvent]?
}

private struct GCalEvent: Decodable {
    let id: String
    let summary: String?
    let start: GCalDateTime?
    let end: GCalDateTime?
    let location: String?
    let attendees: [GCalAttendee]?
    let eventType: String?
    let status: String?
    let hangoutLink: String?
}

private struct GCalDateTime: Decodable {
    let date: String?
    let dateTime: String?
}

private struct GCalAttendee: Decodable {
    let email: String
    let displayName: String?
    let responseStatus: String?
    let isSelf: Bool?
    let resource: Bool?

    enum CodingKeys: String, CodingKey {
        case email, displayName, responseStatus
        case isSelf = "self"
        case resource
    }

    var emailDomain: String? {
        email.split(separator: "@").last.map { $0.lowercased() }
    }
}

// MARK: - Sync Actor

@ModelActor
public actor CalendarSync {

    public func sync(
        calendarAllowlist: [String],
        days: Int,
        lastDetailedSync: Date?
    ) async throws {
        try await syncAllDayEvents(calendarAllowlist: calendarAllowlist, days: days)
        try await syncDetailedEvents(days: days, lastDetailedSync: lastDetailedSync)
    }

    // MARK: - All-day events from +agenda

    private func syncAllDayEvents(calendarAllowlist: [String], days: Int) async throws {
        let result = try await runProcess(
            gwsPath,
            arguments: ["calendar", "+agenda", "--days", "\(days)", "--format", "json"],
            timeout: .seconds(30)
        )

        let response = try JSONDecoder().decode(GWSAgendaResponse.self, from: result.stdout)
        logger.debug("Agenda: fetched \(response.count) events")

        let events: [GWSAgendaEvent]
        if calendarAllowlist.isEmpty {
            events = response.events
        } else {
            events = response.events.filter { calendarAllowlist.contains($0.calendar) }
        }

        for event in events {
            try Task.checkCancellation()
            guard !event.start.contains("T") else { continue }
            try upsertAgendaEvent(event)
        }

        try modelContext.save()
        logger.info(
            "Agenda sync: processed \(events.filter { !$0.start.contains("T") }.count) all-day events"
        )
    }

    private func upsertAgendaEvent(_ event: GWSAgendaEvent) throws {
        guard let startTime = parseDate(event.start),
            let endTime = parseDate(event.end)
        else {
            logger.warning("Skipping all-day event with unparseable dates: \(event.summary)")
            return
        }

        let externalID = "\(event.calendar)|\(event.summary)|\(event.start)"

        let existing = try modelContext.fetch(
            FetchDescriptor<CalendarEvent>(
                predicate: #Predicate { $0.externalID == externalID }
            )
        ).first

        let calEvent: CalendarEvent
        if let existing {
            calEvent = existing
        } else {
            calEvent = CalendarEvent(
                title: event.summary,
                startTime: startTime,
                endTime: endTime,
                externalID: externalID
            )
            modelContext.insert(calEvent)
        }

        calEvent.title = event.summary
        calEvent.startTime = startTime
        calEvent.endTime = endTime
        calEvent.location = event.location?.isEmpty == true ? nil : event.location
        calEvent.isAllDay = true
    }

    // MARK: - Detailed events from events list

    private func syncDetailedEvents(days: Int, lastDetailedSync: Date?) async throws {
        let startOfWeek = startOfCurrentWeek()
        let timeMax = Calendar.current.date(byAdding: .day, value: days, to: startOfWeek)!

        var params: [String: Any] = [
            "calendarId": "primary",
            "timeMin": iso8601String(startOfWeek),
            "timeMax": iso8601String(timeMax),
            "singleEvents": true,
            // Without this Google omits tombstones entirely and deletions are invisible
            "showDeleted": true,
        ]

        if let lastDetailedSync {
            params["updatedMin"] = iso8601String(lastDetailedSync)
            logger.debug("Incremental fetch, updatedMin: \(self.iso8601String(lastDetailedSync))")
        } else {
            logger.debug("Full fetch, no updatedMin")
        }

        let paramsJSON = try JSONSerialization.data(withJSONObject: params)
        let paramsString = String(data: paramsJSON, encoding: .utf8)!

        let result = try await runProcess(
            gwsPath,
            arguments: ["calendar", "events", "list", "--params", paramsString],
            timeout: .seconds(60)
        )

        let response = try JSONDecoder().decode(GCalListResponse.self, from: result.stdout)
        let items = response.items ?? []
        logger.debug("Events list: fetched \(items.count) events")

        // Tombstones carry no usable payload beyond the id, so they are split off before the
        // filters below, which inspect start dates.
        let tombstones = items.filter { $0.status == "cancelled" }

        let timedEvents = items.filter { event in
            guard event.status != "cancelled" else { return false }
            guard event.eventType != "workingLocation" else { return false }
            guard event.start?.date == nil else { return false }
            return true
        }

        for event in timedEvents {
            try Task.checkCancellation()
            try upsertDetailedEvent(event)
        }

        var deleted = 0
        for tombstone in tombstones {
            try Task.checkCancellation()
            if try deleteCancelledEvent(externalID: tombstone.id) { deleted += 1 }
        }

        try modelContext.save()
        logger.info(
            "Events list sync: processed \(timedEvents.count) timed events, deleted \(deleted) cancelled"
        )
    }

    /// Deletes the local event a tombstone refers to, matching on id alone: a cancelled event
    /// arrives with no summary and a placeholder start date. Returns whether a row was removed.
    private func deleteCancelledEvent(externalID: String) throws -> Bool {
        guard
            let calEvent = try modelContext.fetch(
                FetchDescriptor<CalendarEvent>(
                    predicate: #Predicate { $0.externalID == externalID }
                )
            ).first
        else {
            return false
        }

        logger.info("Deleting cancelled event: \(calEvent.title)")
        calEvent.deleteWithEmptyStubs(in: modelContext)
        return true
    }

    private func upsertDetailedEvent(_ event: GCalEvent) throws {
        guard let startTime = parseGCalDateTime(event.start),
            let endTime = parseGCalDateTime(event.end)
        else {
            logger.warning(
                "Skipping event with unparseable dates: \(event.summary ?? "(no title)")")
            return
        }

        let title = event.summary ?? "(no title)"

        // Try to find existing event by Google event ID
        let googleID = event.id
        var calEvent = try modelContext.fetch(
            FetchDescriptor<CalendarEvent>(
                predicate: #Predicate { $0.externalID == googleID }
            )
        ).first

        // Fallback: match by title + startTime (migrates old +agenda events)
        if calEvent == nil {
            let matchTitle = title
            let matchStart = startTime
            let tolerance: TimeInterval = 120
            calEvent = try modelContext.fetch(
                FetchDescriptor<CalendarEvent>(
                    predicate: #Predicate {
                        $0.title == matchTitle && $0.isAllDay == false
                    }
                )
            ).first(where: { abs($0.startTime.timeIntervalSince(matchStart)) < tolerance })

            if calEvent != nil {
                calEvent!.externalID = googleID
                logger.debug("Migrated legacy event to Google ID: \(title)")
            }
        }

        if calEvent == nil {
            calEvent = CalendarEvent(
                title: title,
                startTime: startTime,
                endTime: endTime,
                externalID: googleID
            )
            modelContext.insert(calEvent!)
        }

        let cal = calEvent!
        // Skipping the rest also keeps a hidden event from linking attendees or growing an
        // interview stub.
        guard !cal.isHidden else { return }

        cal.title = title
        cal.startTime = startTime
        cal.endTime = endTime
        cal.location = event.location?.isEmpty == true ? nil : event.location
        cal.isAllDay = false

        if let meetingURL = event.hangoutLink.flatMap({ URL(string: $0) }) {
            cal.meetingURL = meetingURL
        }

        // Attendee handling
        let humanAttendees = (event.attendees ?? []).filter {
            $0.resource != true && !$0.email.contains("group")  // group.google.com email address
        }
        cal.participantCount = humanAttendees.count
        cal.confirmedCount = humanAttendees.filter { $0.responseStatus == "accepted" }.count

        if humanAttendees.count < 15 {
            try linkAttendees(humanAttendees, to: cal)
        } else {
            cal.attendees = []
        }

        // Interview auto-stub
        if cal.interview == nil && isLikelyInterview(title) {
            let info = extractCandidateInfo(title)
            let interview = Interview(
                date: startTime,
                candidateName: info.candidateName,
                role: info.role
            )
            interview.coInterviewer = try getCoInterviewer(
                humanAttendees,
                candidateName: info.candidateName
            )
            interview.calendarEvent = cal
            modelContext.insert(interview)
            logger.info("Auto-created interview stub for: \(title)")
        }
    }

    private func linkAttendees(_ attendees: [GCalAttendee], to calEvent: CalendarEvent) throws {
        var people: [Person] = []
        for attendee in attendees {
            let email = attendee.email
            let existing = try modelContext.fetch(
                FetchDescriptor<Person>(
                    predicate: #Predicate { $0.email == email }
                )
            ).first

            if let existing {
                people.append(existing)
            } else {
                let name = attendee.displayName ?? email.components(separatedBy: "@").first ?? email
                let person = Person(name: name, email: email)
                modelContext.insert(person)
                people.append(person)
            }
        }
        calEvent.attendees = people
    }

    /// The colleague on the panel, never the candidate. Candidates are external, so an
    /// attendee on a different email domain than mine is the candidate (or a recruiter),
    /// not a co-interviewer.
    private func getCoInterviewer(_ attendees: [GCalAttendee], candidateName: String)
        throws -> Person?
    {
        let myDomain = attendees.first(where: { $0.isSelf == true })?.emailDomain
        let candidate = candidateName.lowercased()
        let match = attendees.first { attendee in
            guard attendee.isSelf != true else { return false }
            // No self attendee means no domain to compare against; skip the check
            // rather than reject everyone.
            if let myDomain, attendee.emailDomain != myDomain { return false }
            return attendee.displayName?.lowercased() != candidate
        }
        guard let other = match else { return nil }
        let email: String = other.email
        let existing = try modelContext.fetch(
            FetchDescriptor<Person>(
                predicate: #Predicate { $0.email == email }
            )
        ).first
        if let existing { return existing }
        let name = other.displayName ?? email.components(separatedBy: "@").first ?? email
        let person = Person(name: name, email: email)
        modelContext.insert(person)
        return person
    }

    // MARK: - Date parsing

    private func parseDate(_ string: String) -> Date? {
        if string.contains("T") {
            return parseISO8601(string)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: string)
    }

    private func parseGCalDateTime(_ dt: GCalDateTime?) -> Date? {
        guard let dt else { return nil }
        if let dateTime = dt.dateTime {
            return parseISO8601(dateTime)
        }
        if let date = dt.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            return formatter.date(from: date)
        }
        return nil
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

func startOfCurrentWeek() -> Date {
    var calendar = Calendar(identifier: .iso8601)  // ISO 8601: week starts Monday
    calendar.timeZone = .current

    let now = Date()

    // Midnight on the Monday of the current week
    return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
}
