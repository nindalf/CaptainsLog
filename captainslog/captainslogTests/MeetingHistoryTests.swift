import CaptainsLogKit
import Foundation
import Testing

struct MeetingHistoryTests {
    private let me = Person(name: "Me")
    private let tom = Person(name: "Tom")
    private let ana = Person(name: "Ana")
    private let raj = Person(name: "Raj")

    private func event(_ externalID: String) -> CalendarEvent {
        CalendarEvent(title: "e", startTime: .now, endTime: .now, externalID: externalID)
    }

    private func meeting(_ daysAgo: Int, _ people: [Person], event externalID: String? = nil) -> Meeting {
        let m = Meeting(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!, title: "m\(daysAgo)")
        m.attendees = people
        m.calendarEvent = externalID.map(event)
        return m
    }

    @Test func seriesIDComesFromTheInstanceID() {
        #expect(event("fve0tbvucakdjc6s5o0sbgnmeo_20261102T100000Z").seriesID == "fve0tbvucakdjc6s5o0sbgnmeo")
        #expect(event("93knog7j44mfvijur6jh31s5l0_20261027").seriesID == "93knog7j44mfvijur6jh31s5l0")
        #expect(event("3q1lbd8hr0mpkj2n1tkgs1v8pe").seriesID == nil)
        // All-day rows from before Google ids
        #expect(event("Holidays|Bank holiday|2026-08-31").seriesID == nil)
    }

    @Test func earlierInstancesOfTheSeriesMatchWhoeverAttended() {
        let now = meeting(0, [me, tom, ana], event: "abc_20261105T100000Z")
        let last = meeting(7, [me, raj], event: "abc_20261029T100000Z")
        let other = meeting(3, [me, raj], event: "xyz_20261102T100000Z")
        let found = now.previous(among: [last, other], me: me.id)
        #expect(found.map(\.meeting.title) == ["m7"])
        #expect(found.first?.match == .series)
    }

    @Test func otherMeetingsMatchOnMostlyTheSamePeopleLeavingMeOut() {
        let now = meeting(0, [me, tom])
        let oneOnOne = meeting(2, [me, tom])
        let group = meeting(1, [me, tom, ana, raj])
        let withAna = meeting(5, [me, tom, ana])
        let later = meeting(-1, [me, tom])
        let found = now.previous(among: [oneOnOne, group, withAna, later], me: me.id)
        // Half of everyone in either counts; a quarter doesn't. Future meetings never do.
        #expect(found.map(\.meeting.title) == ["m2", "m5"])
        #expect(found.allSatisfy { $0.match == .attendees })
    }

    @Test func taggedTodosAreOpenOnesForAnAttendee() {
        let forTom = Todo(title: "a"); forTom.people = [tom]
        let forRaj = Todo(title: "b"); forRaj.people = [raj]
        let done = Todo(title: "c"); done.people = [tom]; done.completedDate = .now
        let filed = Todo(title: "d"); filed.people = [tom]
        let found = MeetingTodos.tagging([tom.id, ana.id], among: [forTom, forRaj, done, filed], excluding: [filed.id])
        #expect(found.map(\.title) == ["a"])
    }
}
