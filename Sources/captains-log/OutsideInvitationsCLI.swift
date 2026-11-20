import ArgumentParser
import CaptainsLogKit
import Foundation

/// Settings › Privacy, read once per run. Lists leave out what it withholds; looking one up by id
/// is an error (`OutsideInvitations.swift`).
let outsideInvitations = OutsideInvitations(withholds: AppSettings().hidesOutsideInvitations)

func withheldError(_ id: UUID) -> ValidationError {
    ValidationError(
        "\(id.uuidString) is from an invitation from outside your organisation that you haven't accepted. "
            + "The CLI leaves it out until you accept it or write in its meeting or interview (Settings › Privacy in the app)"
    )
}

extension OutsideInvitations {
    func require(_ event: CalendarEvent) throws { guard shows(event) else { throw withheldError(event.id) } }
    func require(_ meeting: Meeting) throws { guard shows(meeting) else { throw withheldError(meeting.id) } }
    func require(_ interview: Interview) throws { guard shows(interview) else { throw withheldError(interview.id) } }
}
