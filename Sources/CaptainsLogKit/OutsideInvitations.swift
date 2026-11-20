import Foundation

// Anyone can send an invitation, so an event from outside my domain carries text a stranger wrote:
// its title, location and attendees' names, and the meeting or interview made from it. The CLI,
// which agents read, leaves such an event and its records out until I vouch for it by accepting
// the invitation or writing in its meeting or interview. Settings › Privacy turns this off.

extension CalendarEvent {
    public var isWithheldFromAgents: Bool {
        isFromOutside && !isAcceptedByMe
            && !(meeting?.hasWrittenNotes ?? false)
            && (interview?.isEmpty ?? true)
    }
}

extension Meeting {
    /// Notes, a summary or a transcript: what I write or paste in. Prep notes don't count, since an
    /// agent writes them.
    public var hasWrittenNotes: Bool {
        [notes, summary, transcript].contains { $0?.isEmpty == false }
    }

    public var isWithheldFromAgents: Bool { calendarEvent?.isWithheldFromAgents ?? false }
}

extension Interview {
    public var isWithheldFromAgents: Bool { calendarEvent?.isWithheldFromAgents ?? false }
}

/// Whether the outside-invitation rule applies, read once from Settings.
public struct OutsideInvitations: Sendable {
    public let withholds: Bool

    public init(withholds: Bool) { self.withholds = withholds }

    public static let shown = OutsideInvitations(withholds: false)

    public func shows(_ event: CalendarEvent) -> Bool { !withholds || !event.isWithheldFromAgents }
    public func shows(_ meeting: Meeting) -> Bool { !withholds || !meeting.isWithheldFromAgents }
    public func shows(_ interview: Interview) -> Bool { !withholds || !interview.isWithheldFromAgents }
}

extension GoogleCalendarEvent {
    /// Organised outside `myDomain`. An event on a shared calendar (a group or resource
    /// calendar, organised by the calendar itself) counts by who created it. Fails closed: an event
    /// with no organiser, or with my domain unknown, is from outside unless I organised it.
    public func isFromOutside(myDomain: String?) -> Bool {
        guard let organizer else { return true }
        if organizer.isSelf == true { return false }
        guard let myDomain = myDomain?.lowercased() else { return true }
        let byOrganizer = organizer.email.flatMap(emailDomain)
        if byOrganizer == myDomain { return false }
        if byOrganizer?.hasSuffix(".calendar.google.com") == true {
            if creator?.isSelf == true { return false }
            return creator?.email.flatMap(emailDomain) != myDomain
        }
        return true
    }

    public var isAcceptedByMe: Bool {
        attendees?.contains { $0.isSelf == true && $0.responseStatus == "accepted" } == true
    }
}

extension GoogleCalendarAttendee {
    /// What sync names this attendee: a new one gets the invitation's display name only from a
    /// `trusted` event, else their email's local part. Nil keeps `existing`'s name. Someone still
    /// named from their email, and not named by me, takes the display name from an event organised
    /// inside my domain, so a stranger's invitation never renames anyone.
    public func name(existing: Person?, trusted: Bool, fromInside: Bool) -> String? {
        let fromEmail = email.components(separatedBy: "@").first ?? email
        guard let existing else { return trusted ? displayName ?? fromEmail : fromEmail }
        guard fromInside, let displayName, existing.name == fromEmail, !existing.isAddedManually else { return nil }
        return displayName
    }
}

/// The part after the `@`, lowercased; nil without exactly one.
func emailDomain(_ email: String) -> String? {
    let parts = email.split(separator: "@")
    guard parts.count == 2, !parts[1].isEmpty else { return nil }
    return parts[1].lowercased()
}
