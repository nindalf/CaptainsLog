import SwiftUI
import SwiftData
import CaptainsLogKit

@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let schema = Schema(CaptainsLogSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        populateSampleData(container.mainContext)
        return container
    }()

    static let settings = AppSettings()

    static let syncCoordinator: SyncCoordinator = {
        SyncCoordinator(container: container, settings: settings)
    }()

    // MARK: - Factory methods

    static func makeLogEntry(
        title: String = "Fixed deploy pipeline timeout",
        content: String = "Updated CI config to cache Swift packages, cutting build time from 12m to 4m"
    ) -> LogEntry {
        let entry = LogEntry(timestamp: .now, source: .manual, title: title, content: content)
        container.mainContext.insert(entry)
        return entry
    }

    static func makeMeeting(
        title: String = "Promotions Rules Sync",
        hasNotes: Bool = true
    ) -> Meeting {
        let meeting = Meeting(date: .now, title: title)
        if hasNotes {
            meeting.prepNotes = "Review Q2 promotion backfill agreement"
            meeting.notes = "Discussed batch disagreements on the new multibuy rules. Action: check orders placed around midnight."
            meeting.summary = "Reviewed backfill agreement; agreed to trust streaming over batch on midnight orders."
        }
        container.mainContext.insert(meeting)
        return meeting
    }

    static func makePR(
        title: String = "Add compound index on orders",
        number: Int = 4521,
        state: PRState = .open,
        isAuthoredByMe: Bool = true,
        isDraft: Bool = false,
        reviewDecision: ReviewDecision? = .approved
    ) -> PullRequest {
        let pr = PullRequest(
            number: number,
            title: title,
            url: URL(string: "https://github.com/larder/fulfilment/pull/\(number)")!,
            repo: "larder/fulfilment",
            state: state,
            createdAt: .now.addingTimeInterval(-86400),
            isAuthoredByMe: isAuthoredByMe
        )
        pr.isDraft = isDraft
        pr.reviewDecision = reviewDecision
        pr.additions = 142
        pr.deletions = 38
        pr.body = "Adds a compound index on (customer_id, created_at) to speed up the order history query that powers the account screen."
        container.mainContext.insert(pr)
        return pr
    }

    static func makeInterview(
        candidateName: String = "Alex Chen",
        role: String? = "Backend Engineer"
    ) -> Interview {
        let interview = Interview(date: .now, candidateName: candidateName, role: role)
        interview.problemName = "Rate Limiter"
        interview.rawNotes = "+ Good breakdown of requirements\nx Struggled with concurrent access\n? Moved to distributed case without prompting\nH Suggested thinking about clock skew"
        interview.upsides = "- _Is able to reason from first principles_\n- _Arrives at a working solution_"
        interview.riskFactors = "- _Did not reason effectively about edge cases & partial failure_"
        interview.recommendation = .yes
        interview.levelAssessment = "Mid-level"
        interview.conclusion = "Solid problem-solving, gaps in concurrency knowledge but shows strong potential."
        container.mainContext.insert(interview)
        return interview
    }

    static func makePerson(
        name: String = "Alice Park"
    ) -> Person {
        let person = Person(name: name, email: "alice.park@larder.co.uk", githubHandle: "alicepark")
        container.mainContext.insert(person)
        let fb = Feedback(date: .now.addingTimeInterval(-172800), person: person, content: "Strong technical leadership on the promotions migration: clear writing and a thorough rollout plan.")
        container.mainContext.insert(fb)
        return person
    }

    static func makeTodo(
        title: String = "Write Q2 stock accuracy review",
        dueDate: Date? = Calendar.current.startOfDay(for: .now),
        isCompleted: Bool = false
    ) -> Todo {
        let todo = Todo(title: title, dueDate: dueDate)
        if isCompleted { todo.completedDate = .now }
        container.mainContext.insert(todo)
        return todo
    }

    // MARK: - Sample data

    private static func populateSampleData(_ context: ModelContext) {
        let projectRules = Project(name: "Promotions Rules")
        let projectMigration = Project(name: "Delivery Slot Migration")
        context.insert(projectRules)
        context.insert(projectMigration)

        let alice = Person(name: "Alice Park", email: "alice.park@larder.co.uk", githubHandle: "alicepark")
        let bob = Person(name: "Bob Singh", email: "bob.singh@larder.co.uk", slackHandle: "bobsingh")
        context.insert(alice)
        context.insert(bob)

        let entry1 = LogEntry(timestamp: .now.addingTimeInterval(-3600), source: .manual, title: "Deployed multibuy rules v2", content: "Rolled out the new 3 for 2 rules to production. Monitoring basket totals against batch.")
        entry1.project = projectRules
        entry1.tags = ["deployment", "rules"]
        context.insert(entry1)

        let entry2 = LogEntry(timestamp: .now.addingTimeInterval(-7200), source: .slack, title: "Discussed migration rollback plan", content: "Thread with platform team about safe rollback if the slot migration double-books vans.")
        entry2.project = projectMigration
        entry2.people = [alice]
        context.insert(entry2)

        let entry3 = LogEntry(timestamp: .now.addingTimeInterval(-86400), source: .linear, title: "Triaged GRO-482", content: "Investigated spike in checkout timeouts. Root cause: upstream latency from the warehouse stock API.", isPrivate: true)
        entry3.tags = ["incident", "investigation"]
        context.insert(entry3)

        let entry4 = LogEntry(timestamp: .now.addingTimeInterval(-90000), source: .manual, title: "Wrote design doc for live stock checks", content: "")
        context.insert(entry4)

        let today = Calendar.current.startOfDay(for: .now)
        let event1 = CalendarEvent(title: "Fulfilment Standup", startTime: today.addingTimeInterval(9 * 3600), endTime: today.addingTimeInterval(9.5 * 3600), externalID: "evt-standup")
        event1.isRecurring = true
        context.insert(event1)

        let event2 = CalendarEvent(title: "Delivery Slot Migration Review", startTime: today.addingTimeInterval(11 * 3600), endTime: today.addingTimeInterval(12 * 3600), externalID: "evt-migration")
        context.insert(event2)

        let event3 = CalendarEvent(title: "Team Lunch", startTime: today.addingTimeInterval(12.5 * 3600), endTime: today.addingTimeInterval(13.5 * 3600), externalID: "evt-lunch")
        event3.isAllDay = false
        context.insert(event3)

        let event4 = CalendarEvent(title: "Company All-Hands", startTime: today, endTime: today.addingTimeInterval(86400), externalID: "evt-allhands")
        event4.isAllDay = true
        context.insert(event4)

        let meeting1 = Meeting(date: today.addingTimeInterval(9 * 3600), title: "Fulfilment Standup")
        meeting1.attendees = [alice, bob]
        meeting1.notes = "Discussed promotions deployment timeline. Bob to handle staging validation."
        meeting1.prepNotes = "Check latest staging metrics before meeting"
        meeting1.project = projectRules
        meeting1.calendarEvent = event1
        context.insert(meeting1)

        let meeting2 = Meeting(date: today.addingTimeInterval(11 * 3600), title: "Delivery Slot Migration Review")
        meeting2.attendees = [alice]
        meeting2.project = projectMigration
        meeting2.calendarEvent = event2
        context.insert(meeting2)

        let pr1 = PullRequest(number: 4521, title: "Add compound index on orders", url: URL(string: "https://github.com/larder/fulfilment/pull/4521")!, repo: "larder/fulfilment", state: .open, createdAt: .now.addingTimeInterval(-86400), isAuthoredByMe: true)
        pr1.reviewDecision = .approved
        pr1.additions = 142
        pr1.deletions = 38
        pr1.body = "Adds a compound index on (customer_id, created_at) to speed up the order history query that powers the account screen."
        pr1.author = alice
        pr1.project = projectRules
        context.insert(pr1)

        let pr2 = PullRequest(number: 4480, title: "Batch substitution pipeline", url: URL(string: "https://github.com/larder/fulfilment/pull/4480")!, repo: "larder/fulfilment", state: .merged, createdAt: .now.addingTimeInterval(-259200), isAuthoredByMe: true)
        pr2.mergedAt = .now.addingTimeInterval(-86400)
        pr2.additions = 523
        pr2.deletions = 89
        pr2.body = "Replaces the synchronous substitution loop with a batch pipeline that processes up to 1000 order lines per run. Reduces p99 latency from 2s to 200ms."
        pr2.deploymentStatus = .partiallyDeployed
        context.insert(pr2)

        let pr3 = PullRequest(number: 4510, title: "Fix warehouse API retry logic", url: URL(string: "https://github.com/larder/platform/pull/4510")!, repo: "larder/platform", state: .open, createdAt: .now.addingTimeInterval(-43200), isAuthoredByMe: false)
        pr3.reviewDecision = .changesRequested
        pr3.author = bob
        context.insert(pr3)

        let pr4 = PullRequest(number: 4535, title: "WIP: Add demand forecast v3 model", url: URL(string: "https://github.com/larder/fulfilment/pull/4535")!, repo: "larder/fulfilment", state: .open, createdAt: .now.addingTimeInterval(-7200), isAuthoredByMe: false)
        pr4.isDraft = true
        pr4.author = alice
        context.insert(pr4)

        let pr5 = PullRequest(number: 4320, title: "Migrate legacy meal deal rules", url: URL(string: "https://github.com/larder/fulfilment/pull/4320")!, repo: "larder/fulfilment", state: .merged, createdAt: .now.addingTimeInterval(-1_209_600), isAuthoredByMe: true)
        pr5.mergedAt = .now.addingTimeInterval(-1_123_200)
        pr5.additions = 87
        pr5.deletions = 312
        pr5.deploymentStatus = .deployed
        context.insert(pr5)

        let todo1 = Todo(title: "Write Q2 stock accuracy review", dueDate: today)
        todo1.sortOrder = 0
        todo1.project = projectRules
        context.insert(todo1)

        let todo2 = Todo(title: "Review Alice's migration RFC", dueDate: today.addingTimeInterval(-86400))
        todo2.sortOrder = 1
        todo2.project = projectMigration
        context.insert(todo2)

        let todo3 = Todo(title: "Update oncall runbook")
        todo3.sortOrder = 2
        context.insert(todo3)

        let todo4 = Todo(title: "Set up monitoring for multibuy rules v2")
        todo4.sortOrder = 3
        todo4.completedDate = .now.addingTimeInterval(-3600)
        context.insert(todo4)

        let interviewEvent = CalendarEvent(title: "INTERVIEW - Technical - Alex Chen (Backend Engineer)", startTime: today.addingTimeInterval(14 * 3600), endTime: today.addingTimeInterval(15 * 3600), externalID: "evt-interview")
        context.insert(interviewEvent)

        let interview1 = Interview(date: today.addingTimeInterval(14 * 3600), candidateName: "Alex Chen", role: "Backend Engineer")
        interview1.problemName = "Rate Limiter"
        interview1.rawNotes = "+ Good breakdown of requirements\n+ Identified key constraints early\nx Struggled with concurrent access patterns\n? Moved to distributed case without prompting\nH Suggested thinking about clock skew\n+ Recovered well after hint"
        interview1.upsides = "- _Is able to reason from first principles_\n- _Arrives at a working solution_"
        interview1.riskFactors = "- _Did not reason effectively about edge cases & partial failure_"
        interview1.recommendation = .yes
        interview1.levelAssessment = "Mid-level"
        interview1.conclusion = "Solid problem-solving, gaps in concurrency knowledge but shows strong potential."
        interview1.coInterviewer = bob
        interview1.calendarEvent = interviewEvent
        context.insert(interview1)

        let fb1 = Feedback(date: .now.addingTimeInterval(-172800), person: alice, content: "Great work driving the migration RFC: clear writing and a thorough rollback plan.")
        context.insert(fb1)
        let fb2 = Feedback(date: .now.addingTimeInterval(-864000), person: bob, content: "Reviews are thorough but sometimes slow to turn around.")
        context.insert(fb2)

        // Calendar-only person: should be filtered out of the People tab as noise.
        let vendor = Person(name: "vendor.contact@example.com", email: "vendor.contact@example.com")
        context.insert(vendor)
        let vendorEvent = CalendarEvent(title: "Vendor Sync", startTime: today.addingTimeInterval(16 * 3600), endTime: today.addingTimeInterval(16.5 * 3600), externalID: "evt-vendor")
        vendorEvent.attendees = [vendor]
        context.insert(vendorEvent)

        try? context.save()
    }
}

extension View {
    func previewEnvironment() -> some View {
        self
            .modelContainer(PreviewData.container)
            .environment(PreviewData.settings)
            .environment(PreviewData.syncCoordinator)
            .environment(Navigator())
    }
}
