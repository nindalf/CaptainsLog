import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.nindalf.captainslog", category: "sync.calendar")

// MARK: - Sync Actor

@ModelActor
public actor CalendarSync {

    /// Fetches every synced calendar over the whole window and makes the store match it: adds and
    /// updates what Google returns, and removes what it no longer does. Timed events come only from
    /// the primary calendar; all-day events from the allowlisted calendars (all, when it's empty).
    /// With `hidesOutsideInvitations`, people first met on an invitation from outside that I haven't
    /// accepted are named from their email, not the name the invitation gave them (`OutsideInvitations`).
    public func sync(calendarAllowlist: [String], weeksAhead: Int, hidesOutsideInvitations: Bool) async throws {
        let window = Self.window(around: .now, weeksAhead: weeksAhead)
        // A day wider than the window, so an event on its edge is never judged missing just because
        // Google bounds the range a little differently.
        let fetched = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -1, to: window.start)!,
            end: Calendar.current.date(byAdding: .day, value: 1, to: window.end)!
        )
        let api = GoogleCalendarAPI.shared
        let calendars = try await api.calendars().filter {
            $0.primary == true || Self.isAllowed($0, by: calendarAllowlist)
        }
        // The primary calendar's id is my email.
        let myDomain = calendars.first { $0.primary == true }.flatMap { emailDomain($0.id) }

        var seen = Set<String>()
        var upserted = 0
        for calendar in calendars {
            let keepsTimed = calendar.primary == true
            let keepsAllDay = Self.isAllowed(calendar, by: calendarAllowlist)
            for event in try await api.events(calendarID: calendar.id, in: fetched) {
                try Task.checkCancellation()
                // Declined counts as gone, so an event declined after it synced is removed.
                guard event.status != "cancelled", !event.isDeclinedByMe else { continue }
                // Only the primary calendar gets invitations; other calendars are ones I chose to add.
                let isFromOutside = calendar.primary == true && event.isFromOutside(myDomain: myDomain)
                if event.isAllDay {
                    guard keepsAllDay else { continue }
                    seen.insert(event.id)
                    try upsertAllDayEvent(event, calendarName: calendar.summary ?? calendar.id, isFromOutside: isFromOutside)
                } else {
                    guard keepsTimed, event.eventType != "workingLocation" else { continue }
                    seen.insert(event.id)
                    let trustsNames = !hidesOutsideInvitations || !isFromOutside || event.isAcceptedByMe
                    try upsertTimedEvent(event, isFromOutside: isFromOutside, trustsNames: trustsNames)
                }
                upserted += 1
            }
        }

        let removed = try CalendarEvent.removeMissing(from: window, keeping: seen, in: modelContext)
        try modelContext.save()
        logger.info("Calendar sync: \(upserted) events from \(calendars.count) calendars, removed \(removed)")
    }

    /// From a week back, so a cancellation after the fact still reaches the past week.
    static func window(around now: Date, weeksAhead: Int) -> DateInterval {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return DateInterval(
            start: calendar.date(byAdding: .day, value: -7, to: today)!,
            end: calendar.date(byAdding: .day, value: 7 * weeksAhead, to: today)!
        )
    }

    private static func isAllowed(_ calendar: GoogleCalendarListEntry, by allowlist: [String]) -> Bool {
        guard !allowlist.isEmpty else { return true }
        let names = [calendar.id, calendar.summary?.trimmingCharacters(in: .whitespaces)].compactMap { $0 }
        return allowlist.contains { names.contains($0) }
    }

    // MARK: - Upserting

    private func fetchEvent(externalID: String) throws -> CalendarEvent? {
        try modelContext.fetch(
            FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.externalID == externalID })
        ).first
    }

    /// `legacyID` is a row from before Google ids to adopt, if there's no row by id yet.
    private func findOrInsert(
        _ event: GoogleCalendarEvent, title: String, start: Date, end: Date, adopting legacyID: String? = nil
    ) throws -> CalendarEvent {
        if let existing = try fetchEvent(externalID: event.id) { return existing }
        if let legacyID, let legacy = try fetchEvent(externalID: legacyID) {
            legacy.externalID = event.id
            return legacy
        }
        let calEvent = CalendarEvent(title: title, startTime: start, endTime: end, externalID: event.id)
        modelContext.insert(calEvent)
        return calEvent
    }

    private func upsertAllDayEvent(_ event: GoogleCalendarEvent, calendarName: String, isFromOutside: Bool) throws {
        guard let startTime = parseGCalDateTime(event.start),
            let endTime = parseGCalDateTime(event.end)
        else {
            logger.warning("Skipping all-day event with unparseable dates: \(event.summary ?? "(no title)")")
            return
        }
        let title = event.summary ?? "(no title)"

        // All-day rows from the old `+agenda` sync are keyed by calendar, title and date. Adopting
        // one keeps it hidden, and keeps its meeting.
        let legacyID = "\(calendarName)|\(event.summary ?? "")|\(event.start?.date ?? "")"
        let calEvent = try findOrInsert(event, title: title, start: startTime, end: endTime, adopting: legacyID)
        calEvent.isFromOutside = isFromOutside
        calEvent.isAcceptedByMe = event.isAcceptedByMe
        guard !calEvent.isHidden else { return }

        calEvent.title = title
        calEvent.startTime = startTime
        calEvent.endTime = endTime
        calEvent.location = event.location?.isEmpty == true ? nil : event.location
        calEvent.isAllDay = true
        calEvent.isRecurring = event.recurringEventId != nil
    }

    /// `trustsNames`: whether a new attendee takes the name the invitation gives them.
    private func upsertTimedEvent(_ event: GoogleCalendarEvent, isFromOutside: Bool, trustsNames: Bool) throws {
        guard let startTime = parseGCalDateTime(event.start),
            let endTime = parseGCalDateTime(event.end)
        else {
            logger.warning(
                "Skipping event with unparseable dates: \(event.summary ?? "(no title)")")
            return
        }

        let title = event.summary ?? "(no title)"
        let cal = try findOrInsert(event, title: title, start: startTime, end: endTime)
        // Before the hidden check, so an event hidden before schema V6 is still judged.
        cal.isFromOutside = isFromOutside
        cal.isAcceptedByMe = event.isAcceptedByMe
        // Skipping the rest also keeps a hidden event from linking attendees or growing an
        // interview stub.
        guard !cal.isHidden else { return }

        cal.title = title
        cal.startTime = startTime
        cal.endTime = endTime
        cal.location = event.location?.isEmpty == true ? nil : event.location
        cal.isAllDay = false
        cal.isRecurring = event.recurringEventId != nil
        cal.isOrganizedByMe = event.organizer?.isSelf == true

        if let meetingURL = event.hangoutLink.flatMap({ URL(string: $0) }) {
            cal.meetingURL = meetingURL
        }

        // Attendee handling
        let humanAttendees = (event.attendees ?? []).filter {
            $0.resource != true && !$0.email.contains("group")  // group.google.com email address
        }

        if humanAttendees.count < 15 {
            try linkAttendees(humanAttendees, to: cal, trustsNames: trustsNames, fromInside: !isFromOutside)
            // A meeting's attendees are its event's; nothing else edits them.
            cal.meeting?.attendees = cal.attendees
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
                candidateName: info.candidateName,
                trustsNames: trustsNames,
                fromInside: !isFromOutside
            )
            interview.calendarEvent = cal
            modelContext.insert(interview)
            logger.info("Auto-created interview stub for: \(title)")
        }
    }

    private func linkAttendees(
        _ attendees: [GoogleCalendarAttendee], to calEvent: CalendarEvent, trustsNames: Bool, fromInside: Bool
    ) throws {
        calEvent.attendees = try attendees.map { try person(for: $0, trustsNames: trustsNames, fromInside: fromInside) }
    }

    /// Finds or adds the attendee's person, named as `GoogleCalendarAttendee.name` says.
    private func person(for attendee: GoogleCalendarAttendee, trustsNames: Bool, fromInside: Bool) throws -> Person {
        let email = attendee.email
        let existing = try modelContext.fetch(
            FetchDescriptor<Person>(predicate: #Predicate { $0.email == email })
        ).first
        let name = attendee.name(existing: existing, trusted: trustsNames, fromInside: fromInside)
        if let existing {
            if let name { existing.name = name }
            return existing
        }
        let person = Person(name: name ?? email, email: email)
        modelContext.insert(person)
        return person
    }

    /// The colleague on the panel, never the candidate. Candidates are external, so an
    /// attendee on a different email domain than mine is the candidate (or a recruiter),
    /// not a co-interviewer.
    private func getCoInterviewer(
        _ attendees: [GoogleCalendarAttendee], candidateName: String, trustsNames: Bool, fromInside: Bool
    ) throws -> Person?
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
        return try person(for: other, trustsNames: trustsNames, fromInside: fromInside)
    }

    // MARK: - Date parsing

    private func parseGCalDateTime(_ dt: GoogleCalendarTime?) -> Date? {
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
}
