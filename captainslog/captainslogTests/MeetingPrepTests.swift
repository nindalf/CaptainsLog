import Foundation
import Testing
import CaptainsLogKit

// What `meetings prep` infers: the projects a meeting's attendees work on, and what closed since
// the last meeting. Models are built but never inserted, so no container is needed.
@Suite(.serialized) @MainActor
struct MeetingPrepTests {
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
    private let me = Person(name: "Me")
    private let alice = Person(name: "Alice")
    private let bob = Person(name: "Bob")

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: now)!
    }

    private func meeting(_ offset: Int, with people: [Person]) -> Meeting {
        let m = Meeting(date: day(offset), title: "m")
        m.attendees = people
        return m
    }

    private func todo(_ title: String, project: Project? = nil, people: [Person] = [], completed: Int? = nil, filedIn: Meeting? = nil) -> Todo {
        let t = Todo(title: title)
        t.project = project
        t.people = people
        t.completedDate = completed.map(day)
        t.meeting = filedIn
        return t
    }

    @Test func projectsComeFromTodosTaggingAttendeesOtherThanMe() {
        let tagged = Project(name: "Tagged")
        let mine = Project(name: "Mine")
        let todos = [todo("a", project: tagged, people: [alice]), todo("b", project: mine, people: [me])]
        let projects = MeetingPrep.relatedProjects(for: meeting(1, with: [me, alice]), previous: [], todos: todos, me: me.id, now: now)
        #expect(projects.map(\.name) == ["Tagged"])
    }

    @Test func moreLinksRankHigherAndOldOrDoneProjectsAreLeftOut() {
        let busy = Project(name: "Busy")
        let quiet = Project(name: "Quiet")
        let stale = Project(name: "Stale")
        let done = Project(name: "Done")
        done.completedDate = day(-1)
        let last = meeting(-7, with: [me, alice])
        let todos = [
            todo("a", project: quiet, people: [alice]),
            todo("b", project: busy, people: [alice]),
            todo("c", project: busy, filedIn: last),
            todo("d", project: stale, people: [alice], completed: -90),
            todo("e", project: done, people: [alice]),
        ]
        let projects = MeetingPrep.relatedProjects(for: meeting(1, with: [me, alice]), previous: [last], todos: todos, me: me.id, now: now)
        #expect(projects.map(\.name) == ["Busy", "Quiet"])
    }

    @Test func completedSinceCoversAttendeesAndRelatedProjectsInTheWindow() {
        let project = Project(name: "P")
        let todos = [
            todo("tagged", people: [bob], completed: -2),
            todo("in project", project: project, completed: -1),
            todo("only me", people: [me], completed: -1),
            todo("before last meeting", people: [bob], completed: -10),
            todo("still open", people: [bob]),
        ]
        let done = MeetingPrep.completed(for: meeting(1, with: [me, bob]), since: day(-7), projects: [project], todos: todos, me: me.id)
        #expect(done.map(\.title) == ["in project", "tagged"])
    }

    @Test func recentMeetingsPreferTheSeriesAndTopUpWithTheSamePeople() {
        let newer = meeting(-2, with: [me, alice])
        let older = meeting(-3, with: [me, alice])
        let series = meeting(-7, with: [me, alice])
        let previous: [(meeting: Meeting, match: Meeting.PreviousMatch)] = [(newer, .attendees), (older, .attendees), (series, .series)]
        let found = MeetingPrep.recent(of: previous).map(\.meeting)
        #expect(found.count == 2 && found[0] === newer && found[1] === series)
    }
}
