import CaptainsLogKit

extension DemoSeeder {
    private static let liveStock = DemoProjects.liveStock
    private static let promotions = DemoProjects.promotions
    private static let exceptions = DemoProjects.exceptions
    private static let recalls = DemoProjects.recalls

    /// Roughly seven a list. Next week's Wednesday and Friday are left empty, for the weekly review to fill.
    static let todos: [DemoTodo] = [
        // Today
        DemoTodo(title: "Write the INC-419 actions into the incident doc", when: .daysFromToday(-2), project: exceptions,
                 notes: "From the postmortem: shared idempotency middleware (Priya), replay alert (Marcus). Link the PRs.", meeting: "postmortem"),
        DemoTodo(title: "Review PR Loyalty streak backfill for the last 90 days", when: .daysFromToday(0),
                 pullRequest: "Loyalty streak backfill for the last 90 days"),
        DemoTodo(title: "Finish the load test plan for the 1% dark launch", when: .daysFromToday(0), project: liveStock),
        DemoTodo(title: "Prep the architecture forum slides", when: .daysFromToday(0), project: liveStock,
                 notes: "Numbers from Friday's shadow mode check-in. Ten slides at most.", meeting: "forum"),
        DemoTodo(title: "Reply to @elena with dark launch dates for the product review", when: .daysFromToday(-1), project: liveStock),
        DemoTodo(title: "Draft Q4 goals to go through with @hannah", when: .daysFromToday(0), meeting: "hannah"),
        DemoTodo(title: "Re-review @ben's DSL parser tests", when: .daysFromToday(0), project: promotions,
                 pullRequest: "Table-driven tests for the DSL parser"),

        // Upcoming
        DemoTodo(title: "Present live stock at the architecture forum", when: .on(Slot(1, .mon, 0)), project: liveStock, meeting: "forum"),
        DemoTodo(title: "Kick off rules 31 and 32 with @tomas", when: .on(Slot(1, .mon, 0)), project: promotions),
        DemoTodo(title: "Review the shadow mode disagreements with @owen's shift leads", when: .on(Slot(1, .tue, 0)), project: liveStock,
                 notes: "Owen wants every disagreement reviewed before we go past 5%."),
        DemoTodo(title: "Demo grouped cases to ops with @aisha", when: .on(Slot(1, .thu, 0)), project: exceptions),
        DemoTodo(title: "Walk @ben through the live stock trade-offs", when: .on(Slot(1, .thu, 0))),
        DemoTodo(title: "Start the 1% dark launch", when: .on(Slot(2, .tue, 0)), project: liveStock),
        DemoTodo(title: "Send @sam fallback counts for the trading pack", when: .on(Slot(3, .wed, 0)), project: liveStock),
        DemoTodo(title: "Confirm December on-call cover", when: .on(Slot(5, .mon, 0))),

        // Anytime
        DemoTodo(title: "Decide how warehouse stock corrections reach running pods", when: .anytime, project: liveStock),
        DemoTodo(title: "Show recall list age on the store dashboard", when: .anytime, notes: "Owen has asked in two 1:1s."),
        DemoTodo(title: "Port rule 33: spend £60 across two orders in a week", when: .anytime, project: promotions,
                 notes: "Needs cross-order joins in the DSL first."),
        DemoTodo(title: "Delete the nightly SQL job once rule 40 has two weeks of agreement", when: .anytime, project: promotions),
        DemoTodo(title: "Write up the promotions DSL for the trading team", when: .anytime, project: promotions),
        DemoTodo(title: "Edit history for shift notes", when: .anytime, project: exceptions),
        DemoTodo(title: "Keyboard shortcuts for moving between grouped exceptions", when: .anytime, project: exceptions),

        // Someday
        DemoTodo(title: "Write a blog post on live stock at checkout", when: .someday),
        DemoTodo(title: "Try property-based tests for the promotions DSL", when: .someday, project: promotions),
        DemoTodo(title: "Per-store demand forecasting with @grace", when: .someday),
        DemoTodo(title: "Replace the hand-rolled retry helper with platform/retry", when: .someday),
        DemoTodo(title: "Open-source the product-name test corpus", when: .someday),
        DemoTodo(title: "Automate the weekly stock count reconciliation", when: .someday, project: liveStock),
        DemoTodo(title: "Start a fulfilment tech talk series", when: .someday),

        // Inbox
        DemoTodo(title: "Ask @owen for last month's exception handling times", when: .inbox,
                 notes: "Baseline for the console's 25% target."),
        DemoTodo(title: "Read @grace's write-up on the rule 24 business threshold", when: .inbox),
        DemoTodo(title: "Find out why stock CI takes 14 minutes", when: .inbox),
        DemoTodo(title: "Expense the social pizza receipts", when: .inbox),
        DemoTodo(title: "Rotate the warehouse vendor API key", when: .inbox),
        DemoTodo(title: "Follow up on multipack misses from shadow mode", when: .inbox,
                 notes: "Most of the 0.6% disagreement. Check the pack mapping with Marcus.",
                 pullRequest: "Map multipacks to their single-unit stock"),
        DemoTodo(title: "Book a room for the ops demo", when: .inbox),

        // Logbook
        DemoTodo(title: "Tell food safety and ops about INC-412", when: .anytime, project: recalls, done: Slot(-2, .wed, 8, 10)),
        DemoTodo(title: "Fix the recall feed parser", when: .anytime, project: recalls, done: Slot(-2, .wed, 9, 30)),
        DemoTodo(title: "Re-check orders placed on the stale recall list", when: .anytime, project: recalls, done: Slot(-2, .wed, 11, 30)),
        DemoTodo(title: "Book a room for the design review", when: .anytime, done: Slot(-2, .tue, 12)),
        DemoTodo(title: "Draft the live stock design doc", when: .anytime, project: liveStock, done: Slot(-2, .thu, 11)),
        DemoTodo(title: "Pair with Ben on rule 23 tests", when: .anytime, project: promotions, done: Slot(-2, .thu, 10, 45)),
        DemoTodo(title: "Checksum downloaded recall feeds", when: .anytime, project: recalls, done: Slot(-2, .fri, 15)),
        DemoTodo(title: "Book bowling and pizza for the social", when: .anytime, done: Slot(-1, .mon, 12, 30)),
        DemoTodo(title: "Invite Owen's shift leads to the social", when: .anytime, done: Slot(-1, .mon, 12, 40)),
        DemoTodo(title: "Review PR Map multipacks to their single-unit stock", when: .anytime, done: Slot(-1, .mon, 14),
                 pullRequest: "Map multipacks to their single-unit stock"),
        DemoTodo(title: "Contract test against the recall feed format", when: .anytime, project: recalls, done: Slot(-1, .mon, 15)),
        DemoTodo(title: "Idempotency key on refund draft creation", when: .anytime, project: exceptions, done: Slot(-1, .tue, 12, 30)),
        DemoTodo(title: "Write the recall feed runbook", when: .anytime, project: recalls, done: Slot(-1, .wed, 15)),
        DemoTodo(title: "Run the INC-419 postmortem", when: .anytime, project: exceptions, done: Slot(-1, .thu, 12), meeting: "postmortem"),
        DemoTodo(title: "Benchmark harness for the stock service", when: .anytime, project: liveStock, done: Slot(-1, .fri, 14)),
        DemoTodo(title: "Ask Hannah about capping interviews", when: .anytime, done: Slot(0, .tue, 11, 30), meeting: "hannah"),
        DemoTodo(title: "Review Aisha's shift notes UI", when: .anytime, project: exceptions, done: Slot(0, .tue, 14),
                 pullRequest: "Shift notes on grouped cases"),
        DemoTodo(title: "Port rules 27 and 28", when: .anytime, project: promotions, done: Slot(0, .wed, 17)),
        DemoTodo(title: "Turn on shadow mode at 5%", when: .anytime, project: liveStock, done: Slot(0, .wed, 15)),
        DemoTodo(title: "Send Elena the rollout plan", when: .anytime, project: liveStock, done: Slot(0, .thu, 12, 40)),

        // Trash
        DemoTodo(title: "Set up a 1:1 with the new food safety analyst", when: .inbox, trashed: Slot(-1, .wed, 9)),
        DemoTodo(title: "Investigate consumer lag on staging", when: .inbox, trashed: Slot(0, .tue, 16)),
    ]
}
