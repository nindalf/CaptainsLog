import ArgumentParser
import CaptainsLogKit
import Foundation
import SwiftData

/// Seeds an empty scratch store with demo data for a senior engineer on the fulfilment team at
/// Larder, a grocery delivery startup: the last two weeks, this week and next. Everything is placed
/// relative to this week's Monday; anything that would land after now is left out, or left
/// unwritten if it's on the calendar.
struct SeedDemo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "seed-demo",
        abstract: "Seed demo data into an empty scratch store (UI sandbox only)",
        shouldDisplay: false
    )

    @Flag(name: .long, help: "Pretty-print JSON output")
    var pretty: Bool = false

    mutating func run() async throws {
        guard Store.isScratch else {
            throw ValidationError("seed-demo only runs against a scratch store; set CAPTAINSLOG_STORE_DIR")
        }
        let context = ModelContext(try Store.makeContainer())
        guard try context.fetchCount(FetchDescriptor<Person>()) == 0 else {
            throw ValidationError("seed-demo needs an empty store")
        }
        let counts = try DemoSeeder(context: context, clock: SeedClock(now: .now)).run()
        // A demo store looks freshly synced and backed up, so `status` doesn't open the weekly review with a warning.
        SyncHistory.update { history in
            for source in [SyncSource.github, .calendar, .backup] {
                history.recordSuccess(source)
            }
        }
        try printJSON(counts, pretty: pretty)
    }
}

/// A time in the demo's calendar: a weekday in a week counted from this one (0), at a time of day.
struct Slot {
    enum Day: Int { case mon, tue, wed, thu, fri, sat, sun }

    let week: Int
    let day: Day
    let hour: Int
    let minute: Int

    init(_ week: Int, _ day: Day, _ hour: Int, _ minute: Int = 0) {
        self.week = week
        self.day = day
        self.hour = hour
        self.minute = minute
    }
}

struct SeedClock {
    let now: Date
    let calendar: Calendar
    let monday: Date

    init(now: Date, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        let today = calendar.startOfDay(for: now)
        let sinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        monday = calendar.date(byAdding: .day, value: -sinceMonday, to: today)!
    }

    func date(_ slot: Slot) -> Date {
        let day = calendar.date(byAdding: .day, value: slot.week * 7 + slot.day.rawValue, to: monday)!
        return calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: day)!
    }

    func isPast(_ slot: Slot) -> Bool { date(slot) <= now }

    /// The start of the day `offset` days from today.
    func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    /// The Monday of the week, as the weekly review titles it.
    func mondayLabel(week: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date(Slot(week, .mon, 0)))
    }
}

final class DemoSeeder {
    let context: ModelContext
    let clock: SeedClock
    private var people: [String: Person] = [:]
    private var projects: [String: Project] = [:]
    private var meetings: [String: Meeting] = [:]
    private var interviews: [Interview] = []
    private var prs: [String: PullRequest] = [:]
    private var counts: [String: Int] = [:]

    init(context: ModelContext, clock: SeedClock) {
        self.context = context
        self.clock = clock
    }

    func run() throws -> [String: Int] {
        seedPeople()
        seedProjects()
        seedCalendar()
        seedInterviews()
        seedPullRequests()
        seedLog()
        seedFeedback()
        seedTodos()
        try context.save()
        return counts
    }

    private func count(_ key: String) { counts[key, default: 0] += 1 }

    private func person(_ key: String) -> Person {
        guard let person = people[key] else { preconditionFailure("seed-demo: no person \(key)") }
        return person
    }

    private func project(_ name: String?) -> Project? {
        guard let name else { return nil }
        guard let project = projects[name] else { preconditionFailure("seed-demo: no project \(name)") }
        return project
    }

    // MARK: People and projects

    private func seedPeople() {
        for seed in Self.people {
            let person = Person(name: seed.name, email: seed.email, slackHandle: seed.key, githubHandle: seed.github)
            person.syncsPullRequests = seed.syncsPullRequests
            context.insert(person)
            people[seed.key] = person
            count("people")
        }
        // On calendar events only, so the People tab leaves her out.
        let recruiter = Person(name: "Jess Moore", email: "jess.moore@larder.co.uk")
        context.insert(recruiter)
        people["jess"] = recruiter
    }

    private func seedProjects() {
        for (index, seed) in Self.projects.enumerated() {
            let project = Project(name: seed.name)
            project.notes = seed.notes
            project.iconName = seed.icon
            project.sortOrder = index
            if let completed = seed.completed, clock.isPast(completed) {
                ProjectCompletion.complete(project, openTodos: [], now: clock.date(completed))
            }
            context.insert(project)
            projects[seed.name] = project
            count("projects")
        }
    }

    private func seedFeedback() {
        for seed in Self.people {
            for item in seed.feedback where clock.isPast(item.slot) {
                context.insert(Feedback(date: clock.date(item.slot), person: person(seed.key), content: item.content))
                count("feedback")
            }
        }
    }

    // MARK: Calendar, meetings and interviews

    private func insertEvent(_ title: String, at slot: Slot, minutes: Int, attendees: [String], location: String?, id: String) -> CalendarEvent {
        let start = clock.date(slot)
        let event = CalendarEvent(title: title, startTime: start, endTime: start.addingTimeInterval(Double(minutes) * 60), externalID: "seed-\(id)")
        event.location = location
        context.insert(event)
        event.attendees = attendees.map(person)
        event.participantCount = attendees.count + 1
        event.confirmedCount = attendees.count + 1
        count("events")
        return event
    }

    private func seedCalendar() {
        let squad = ["hannah", "priya", "marcus", "aisha", "tomas", "ben", "elena"]
        for week in -2...1 {
            for day in [Slot.Day.mon, .tue, .wed, .thu, .fri] {
                let event = insertEvent("Fulfilment standup", at: Slot(week, day, 9, 45), minutes: 15, attendees: squad, location: nil, id: "standup-\(week)-\(day.rawValue)")
                event.isRecurring = true
                event.meetingURL = URL(string: "https://meet.google.com/kfc-stnd-upx")
            }
        }

        for (index, seed) in Self.meetings.enumerated() {
            let event = insertEvent(seed.title, at: seed.slot, minutes: seed.minutes, attendees: seed.attendees, location: seed.location, id: "meeting-\(index)")
            event.isRecurring = seed.recurring
            let isPast = clock.isPast(seed.slot)
            let notes = isPast ? seed.notes : nil
            guard notes != nil || seed.prep != nil else { continue }
            let meeting = event.createMeeting(in: context)
            meeting.prepNotes = seed.prep
            meeting.notes = notes
            meeting.summary = isPast ? seed.summary : nil
            meeting.project = project(seed.project)
            if let key = seed.key { meetings[key] = meeting }
            count("meetings")
        }

        let social = Slot(-1, .thu, 17, 30)
        _ = insertEvent("Fulfilment social: bowling and pizza", at: social, minutes: 150,
                        attendees: ["hannah", "priya", "marcus", "aisha", "tomas", "ben", "elena", "owen", "grace", "sam"],
                        location: "Strike & Slice, Shoreditch", id: "social")

        // All-day events from the team calendar: one shown, one the user hid.
        let away = insertEvent("Hannah out of office", at: Slot(0, .thu, 0), minutes: 2 * 24 * 60, attendees: [], location: nil, id: "hannah-ooo")
        away.isAllDay = true
        let offsite = insertEvent("Checkout offsite", at: Slot(0, .wed, 0), minutes: 2 * 24 * 60, attendees: [], location: nil, id: "checkout-offsite")
        offsite.isAllDay = true
        offsite.isHidden = true
    }

    private func seedInterviews() {
        for (index, seed) in Self.interviews.enumerated() {
            let title = "INTERVIEW - \(seed.format) - \(seed.candidate) (\(seed.role))"
            let event = insertEvent(title, at: seed.slot, minutes: 60, attendees: [seed.coInterviewer, "jess"], location: "Google Meet", id: "interview-\(index)")
            // As calendar sync stubs it: candidate, role and co-interviewer.
            let interview = Interview(date: event.startTime, candidateName: seed.candidate, role: seed.role)
            context.insert(interview)
            interview.calendarEvent = event
            interview.coInterviewer = person(seed.coInterviewer)
            if clock.isPast(seed.slot), let card = seed.scorecard {
                interview.problemName = card.problem
                interview.rawNotes = card.rawNotes
                interview.upsides = card.upsides
                interview.riskFactors = card.risks
                interview.levelAssessment = card.level
                interview.recommendation = card.recommendation
                interview.conclusion = card.conclusion
                let debrief = clock.calendar.date(byAdding: .day, value: 1, to: event.startTime)!
                if let notes = card.debrief, debrief <= clock.now {
                    interview.debriefDate = debrief
                    interview.debriefNotes = notes
                }
            }
            interviews.append(interview)
            count("interviews")
        }
    }

    // MARK: Pull requests

    private func seedPullRequests() {
        var next: [DemoRepo: Int] = [.stock: 1408, .promoRules: 586, .exceptions: 231, .platform: 917]
        let ordered = Self.pullRequests.enumerated().sorted {
            (clock.date($0.element.slot), $0.offset) < (clock.date($1.element.slot), $1.offset)
        }
        for (_, seed) in ordered {
            let number = next[seed.repo]!
            next[seed.repo] = number + 1
            guard clock.isPast(seed.slot) else { continue }
            let created = clock.date(seed.slot)
            let repo = "larder/\(seed.repo.rawValue)"
            let pr = PullRequest(number: number, title: seed.title, url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
                                 repo: repo, state: .open, createdAt: created, isAuthoredByMe: seed.author == nil)
            pr.body = seed.body
            pr.notes = seed.notes
            pr.additions = seed.additions
            pr.deletions = seed.deletions
            pr.isTeammateOnly = seed.teammateOnly

            let merged = created.addingTimeInterval(Double(seed.mergeAfterHours) * 3600)
            switch seed.outcome {
            case .prod, .staging, .merged:
                if merged <= clock.now {
                    pr.state = .merged
                    pr.mergedAt = merged
                    pr.reviewDecision = .approved
                    pr.deploymentStatus = seed.outcome == .prod ? .deployed : seed.outcome == .staging ? .partiallyDeployed : .notDeployed
                } else {
                    pr.reviewDecision = .approved
                }
            case .open(let decision):
                pr.reviewDecision = decision
            case .draft:
                pr.isDraft = true
            case .closed:
                pr.state = .closed
            }
            // I approved every review request that got approved, an hour before it merged.
            if seed.author != nil, !seed.teammateOnly, pr.reviewDecision == .approved {
                pr.myReviewedAt = min(max(created, merged.addingTimeInterval(-3600)), clock.now)
            }
            context.insert(pr)
            pr.author = seed.author.map(person)
            pr.reviewers = seed.reviewers.map(person)
            pr.project = project(seed.project)
            prs[seed.title] = pr
            count(seed.author == nil ? "prsMine" : "prsTeammates")
        }
    }

    // MARK: Log

    private func seedLog() {
        for seed in Self.logEntries where clock.isPast(seed.slot) {
            let title = seed.tags.contains("weekly-review") ? "\(seed.title): \(clock.mondayLabel(week: seed.slot.week))" : seed.title
            let entry = LogEntry(timestamp: clock.date(seed.slot), source: seed.source, title: title, content: seed.content, isPrivate: seed.isPrivate)
            entry.tags = seed.tags
            context.insert(entry)
            entry.project = project(seed.project)
            entry.linkMentionedPeople(among: Array(people.values))
            count("logEntries")
        }
    }

    // MARK: Todos

    private func seedTodos() {
        var sortOrder = 0
        func insert(_ todo: Todo) {
            todo.sortOrder = sortOrder
            sortOrder += 1
            context.insert(todo)
            count("todos")
        }

        for seed in Self.todos {
            let todo = Todo(title: seed.title)
            todo.notes = seed.notes
            switch seed.when {
            case .inbox: todo.setUndated(.inbox)
            case .anytime: todo.setUndated(.anytime)
            case .someday: todo.setUndated(.someday)
            case .daysFromToday(let offset): todo.schedule(on: clock.day(offset), calendar: clock.calendar)
            case .on(let slot): todo.schedule(on: clock.date(slot), calendar: clock.calendar)
            }
            if let done = seed.done {
                todo.completedDate = min(clock.date(done), clock.now)
            }
            if let trashed = seed.trashed {
                todo.moveToTrash(now: min(clock.date(trashed), clock.now))
            }
            insert(todo)
            todo.project = project(seed.project)
            todo.meeting = seed.meeting.flatMap { meetings[$0] }
            // A PR opened later than now isn't seeded, so its todo goes without the link.
            if let pr = seed.pullRequest.flatMap({ prs[$0] }) {
                todo.pullRequest = pr
                if todo.notes == nil { todo.notes = pr.url.absoluteString }
            }
            todo.linkMentionedPeople(among: Array(people.values))
        }

        // Every written-up interview got its scorecard todo, and the scorecard went in.
        for interview in interviews where interview.recommendation != nil {
            let todo = Todo(title: ScorecardTodo.title(for: interview))
            todo.schedule(on: interview.date, calendar: clock.calendar)
            todo.completedDate = min(interview.date.addingTimeInterval(3 * 3600), clock.now)
            insert(todo)
            todo.interview = interview
        }
    }
}

// MARK: Seed types

struct DemoPerson {
    let key: String
    let name: String
    let email: String
    let github: String?
    let syncsPullRequests: Bool
    let feedback: [DemoFeedback]
}

struct DemoFeedback {
    let slot: Slot
    let content: String
}

struct DemoProject {
    let name: String
    let icon: String
    let notes: String
    let completed: Slot?
}

struct DemoMeeting {
    let title: String
    let slot: Slot
    var minutes: Int = 30
    let attendees: [String]
    var location: String? = nil
    var project: String? = nil
    var recurring: Bool = true
    /// Names the meeting for todos to link to.
    var key: String? = nil
    var prep: String? = nil
    var notes: String? = nil
    var summary: String? = nil
}

struct DemoScorecard {
    let problem: String
    let rawNotes: String
    let upsides: String
    let risks: String
    let level: String
    let recommendation: Recommendation
    let conclusion: String
    let debrief: String?
}

struct DemoInterview {
    let candidate: String
    let role: String
    let format: String
    let slot: Slot
    let coInterviewer: String
    var scorecard: DemoScorecard? = nil
}

enum DemoRepo: String {
    case stock, promoRules = "promo-rules", exceptions = "exceptions-console", platform = "fulfilment-platform"
}

enum DemoOutcome: Equatable {
    case prod, staging, merged, open(ReviewDecision), draft, closed
}

struct DemoPR {
    let repo: DemoRepo
    let title: String
    let slot: Slot
    /// Nil for my own PRs.
    var author: String? = nil
    var reviewers: [String] = []
    var project: String? = nil
    let outcome: DemoOutcome
    var mergeAfterHours: Int = 5
    let additions: Int
    let deletions: Int
    let body: String
    var notes: String? = nil
    var teammateOnly: Bool = false
}

struct DemoLogEntry {
    let slot: Slot
    let source: EntrySource
    var isPrivate = false
    let title: String
    let tags: [String]
    var project: String? = nil
    let content: String
}

enum DemoWhen {
    case inbox, anytime, someday
    case daysFromToday(Int)
    case on(Slot)
}

struct DemoTodo {
    let title: String
    let when: DemoWhen
    var project: String? = nil
    var notes: String? = nil
    var done: Slot? = nil
    var trashed: Slot? = nil
    /// Key of a meeting in `DemoSeeder.meetings`.
    var meeting: String? = nil
    /// Title of a PR in `DemoSeeder.pullRequests`.
    var pullRequest: String? = nil
}

enum DemoProjects {
    static let liveStock = "Live stock at checkout"
    static let promotions = "Promotions engine migration"
    static let exceptions = "Picker exceptions console"
    static let recalls = "Recall feed hardening"
}
