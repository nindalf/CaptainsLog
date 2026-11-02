import CaptainsLogKit

extension DemoSeeder {
    private static let liveStock = DemoProjects.liveStock
    private static let promotions = DemoProjects.promotions
    private static let exceptions = DemoProjects.exceptions
    private static let recalls = DemoProjects.recalls

    static let pullRequests: [DemoPR] = [
        // Mine, two weeks ago
        DemoPR(repo: .stock, title: "Prototype a Redis-backed stock cache", slot: Slot(-2, .mon, 11), reviewers: ["priya"], project: liveStock,
               outcome: .closed, additions: 412, deletions: 3,
               body: "Spike to see whether a shared Redis cache is fast enough for live stock at checkout. It is at p50, but p99 doubles under Sunday evening load. Closing in favour of the in-process ledger in the design doc."),
        DemoPR(repo: .promoRules, title: "Port rule 21: win-back discount for lapsed customers", slot: Slot(-2, .mon, 14), reviewers: ["tomas"], project: promotions,
               outcome: .prod, additions: 186, deletions: 12,
               body: "Moves rule 21 to the streaming engine. The backfill over 90 days of baskets matches batch exactly."),
        DemoPR(repo: .platform, title: "Bump kafka-go to v0.4.47", slot: Slot(-2, .mon, 16, 30), reviewers: ["marcus"],
               outcome: .prod, additions: 14, deletions: 14,
               body: "Picks up the fix for consumer group rebalances hanging on broker restarts."),
        DemoPR(repo: .promoRules, title: "Port rule 22: mix-and-match 3 for 2", slot: Slot(-2, .tue, 9, 30), reviewers: ["tomas", "grace"], project: promotions,
               outcome: .prod, additions: 203, deletions: 9,
               body: "Rule 22 on streaming. Batch disagrees on 0.3% of baskets, all orders placed just before midnight that batch priced with the next day's promotions. Streaming is right; noted for trading."),
        DemoPR(repo: .exceptions, title: "Remove unused v1 exception serializers", slot: Slot(-2, .tue, 13), reviewers: ["aisha"],
               outcome: .prod, additions: 6, deletions: 534,
               body: "Nothing has called the v1 serializers since the API moved to v2 in June."),
        DemoPR(repo: .stock, title: "Per-stage latency histograms in the stock service", slot: Slot(-2, .tue, 16), reviewers: ["marcus"], project: liveStock,
               outcome: .prod, additions: 97, deletions: 8,
               body: "Load basket, resolve SKUs, look up stock and respond each get a histogram, so we have a baseline before the live work."),
        DemoPR(repo: .stock, title: "Fail the recall refresh on unknown or missing columns", slot: Slot(-2, .wed, 8, 30), reviewers: ["priya"], project: recalls,
               outcome: .prod, mergeAfterHours: 1, additions: 64, deletions: 11,
               body: "Fixes INC-412. The recall feed gained a column and the parser logged a warning and exited 0. Now unknown columns are ignored with a metric, and missing ones fail the job."),
        DemoPR(repo: .stock, title: "Script to re-check orders placed on a stale recall list", slot: Slot(-2, .wed, 9, 30), reviewers: ["marcus"], project: recalls,
               outcome: .prod, mergeAfterHours: 1, additions: 148, deletions: 0,
               body: "Re-checks every order in a time range against the current recall list and writes hits to the food safety queue. Used for INC-412: 14,212 orders, no hits."),
        DemoPR(repo: .promoRules, title: "Fix flaky TestPromoWindow around midnight UTC", slot: Slot(-2, .wed, 15), reviewers: ["ben"],
               outcome: .prod, additions: 22, deletions: 9,
               body: "The test used the wall clock, so it failed for 10 minutes either side of midnight. Injects the clock instead."),
        DemoPR(repo: .stock, title: "Alert when the recall list is more than 6 hours old", slot: Slot(-2, .thu, 9), reviewers: ["priya"], project: recalls,
               outcome: .prod, additions: 31, deletions: 4,
               body: "Was 24 hours, which is why INC-412 took 29 hours to notice. Pages on-call at 6 hours, warns in Slack at 3."),
        DemoPR(repo: .stock, title: "Design doc: live stock checks on the checkout path", slot: Slot(-2, .thu, 11), reviewers: ["priya", "marcus", "grace"], project: liveStock,
               outcome: .merged, mergeAfterHours: 28, additions: 286, deletions: 0,
               body: "In-process stock ledger, 150ms p99 budget, snapshot fallback above 250ms, shadow mode for two weeks. Discussed in Thursday's design review."),
        DemoPR(repo: .promoRules, title: "Port rule 23: London dark store pricing", slot: Slot(-2, .thu, 16), reviewers: ["tomas"], project: promotions,
               outcome: .prod, additions: 241, deletions: 17,
               body: "Rule 23 on streaming. The store list now comes from the store config service instead of a hardcoded table."),
        DemoPR(repo: .stock, title: "Verify checksums of downloaded recall feeds", slot: Slot(-2, .fri, 10), reviewers: ["marcus"], project: recalls,
               outcome: .prod, additions: 58, deletions: 6,
               body: "Rejects a feed whose SHA-256 doesn't match the manifest, instead of loading a truncated file."),
        DemoPR(repo: .platform, title: "Delete the deprecated alerting client", slot: Slot(-2, .fri, 13), reviewers: ["priya"],
               outcome: .prod, additions: 3, deletions: 811,
               body: "Every service is on the new alerting client since last month."),
        DemoPR(repo: .promoRules, title: "Shared basket fixtures for rule tests", slot: Slot(-2, .fri, 15, 30), reviewers: ["ben"],
               outcome: .prod, additions: 174, deletions: 302,
               body: "Each rule test built its own baskets. They now share a dozen named ones, which makes the tests shorter and the edge cases easier to see."),

        // Mine, last week
        DemoPR(repo: .stock, title: "Contract test against the recall feed format", slot: Slot(-1, .mon, 9, 30), reviewers: ["priya"], project: recalls,
               outcome: .prod, additions: 119, deletions: 2,
               body: "Runs daily against the published sample file and fails CI if the schema changes, so we hear about it before the nightly refresh does."),
        DemoPR(repo: .promoRules, title: "Port rule 24: free delivery above the basket threshold", slot: Slot(-1, .mon, 11, 30), reviewers: ["grace", "tomas"], project: promotions,
               outcome: .prod, additions: 265, deletions: 21,
               body: "Rule 24 on streaming, fed by Grace's customer segments. Threshold unchanged for now; a business-account threshold is a separate discussion."),
        DemoPR(repo: .exceptions, title: "Group exceptions by SKU in the case API", slot: Slot(-1, .mon, 15), reviewers: ["aisha"], project: exceptions,
               outcome: .prod, additions: 322, deletions: 40,
               body: "Adds a grouped view to the case API. Aisha's heuristics plug in behind it."),
        DemoPR(repo: .exceptions, title: "Idempotency key on refund draft creation", slot: Slot(-1, .tue, 10, 30), reviewers: ["aisha", "marcus"], project: exceptions,
               outcome: .prod, mergeAfterHours: 2, additions: 88, deletions: 14,
               body: "Fixes INC-419. A consumer replay created a second refund draft for the same exception. Drafts are now keyed on exception ID and order ID, and a duplicate insert returns the existing draft."),
        DemoPR(repo: .exceptions, title: "Script to merge duplicate refund drafts", slot: Slot(-1, .tue, 11, 30), author: "aisha", reviewers: ["marcus"], project: exceptions,
               outcome: .prod, mergeAfterHours: 3, additions: 156, deletions: 0,
               body: "Merges the 212 duplicate drafts from INC-419, keeping the one a shift lead edited. Dry-run output attached.",
               notes: "Reviewed during INC-419. Asked for a dry run against the prod snapshot first, which she'd already done."),
        DemoPR(repo: .stock, title: "Build the in-memory stock ledger from pick and delivery events", slot: Slot(-1, .tue, 16), reviewers: ["marcus"], project: liveStock,
               outcome: .prod, additions: 438, deletions: 25,
               body: "The core of live stock. 1.2M SKU-store rows in 310MB, lookups at 0.4ms p99 on a laptop. Marcus is benchmarking on production hardware."),
        DemoPR(repo: .stock, title: "Runbook: recall feed alerts", slot: Slot(-1, .wed, 10), reviewers: ["tomas"], project: recalls,
               outcome: .merged, additions: 92, deletions: 0,
               body: "What each recall alert means, how to refresh by hand, and when to call food safety."),
        DemoPR(repo: .promoRules, title: "Port rule 25: buy five in 30 days, sixth free", slot: Slot(-1, .wed, 13, 30), reviewers: ["tomas"], project: promotions,
               outcome: .prod, additions: 198, deletions: 11,
               body: "First rule on Tomás's sliding windows. Backfill agreement 99.9%."),
        DemoPR(repo: .platform, title: "Go 1.25 for the fulfilment services", slot: Slot(-1, .wed, 16), reviewers: ["priya"],
               outcome: .prod, additions: 41, deletions: 38,
               body: "Bumps the toolchain in all four services. No code changes needed."),
        DemoPR(repo: .exceptions, title: "Shift notes API on cases", slot: Slot(-1, .thu, 13, 30), reviewers: ["aisha"], project: exceptions,
               outcome: .prod, additions: 276, deletions: 12,
               body: "Notes belong to the case, not the shift lead, so they survive shift handover. Behind the grouped-cases flag."),
        DemoPR(repo: .promoRules, title: "Port rule 26: two-hour flash discounts", slot: Slot(-1, .thu, 15, 30), reviewers: ["ben"], project: promotions,
               outcome: .prod, additions: 214, deletions: 16,
               body: "Rule 26 on streaming. Ben found an off-by-one at the window boundary while we paired on the tests."),
        DemoPR(repo: .stock, title: "Remove the legacy SOAP warehouse client", slot: Slot(-1, .thu, 17), reviewers: ["marcus"],
               outcome: .prod, mergeAfterHours: 16, additions: 12, deletions: 1_942,
               body: "The warehouse vendor turned off the SOAP endpoint in September. Deletes the client, its generated types and two feature flags."),
        DemoPR(repo: .stock, title: "Benchmark harness for the stock service", slot: Slot(-1, .fri, 10), reviewers: ["marcus"], project: liveStock,
               outcome: .prod, additions: 167, deletions: 4,
               body: "Replays a day of anonymised baskets through the service and reports latency per stage. Runs nightly."),
        DemoPR(repo: .exceptions, title: "Retry with backoff in the exceptions consumer", slot: Slot(-1, .fri, 12), reviewers: ["aisha"],
               outcome: .prod, additions: 49, deletions: 31,
               body: "Replaces the fixed one-second retry that hammered the case DB during INC-419's replay."),
        DemoPR(repo: .promoRules, title: "Backfill comparison report for rules 21-26", slot: Slot(-1, .fri, 14), reviewers: ["grace"], project: promotions,
               outcome: .prod, additions: 133, deletions: 0,
               body: "A daily report of streaming against batch, per rule, so trading can see agreement without asking us."),

        // Mine, this week
        DemoPR(repo: .stock, title: "Live stock client for the checkout service", slot: Slot(0, .mon, 11, 30), reviewers: ["marcus", "priya"], project: liveStock,
               outcome: .prod, additions: 352, deletions: 18,
               body: "Client the checkout service calls before confirming an order. Behind a flag, off everywhere."),
        DemoPR(repo: .promoRules, title: "Port rule 27: first-order discount", slot: Slot(0, .mon, 13), reviewers: ["tomas"], project: promotions,
               outcome: .prod, additions: 207, deletions: 14,
               body: "Rule 27 on streaming. The batch version missed customers who signed up and ordered within the same hour; streaming catches them."),
        DemoPR(repo: .platform, title: "Use platform/config instead of the hand-rolled loader", slot: Slot(0, .mon, 16, 30), reviewers: ["priya"],
               outcome: .prod, additions: 85, deletions: 247,
               body: "Our loader predates the platform library and didn't support hot reload."),
        DemoPR(repo: .stock, title: "Warm the stock ledger before a pod reports ready", slot: Slot(0, .tue, 9, 30), reviewers: ["priya"], project: liveStock,
               outcome: .prod, additions: 73, deletions: 9,
               body: "Priya's catch from the design review: a pod serving before its ledger loads would report everything out of stock. The readiness probe now waits for the ledger."),
        DemoPR(repo: .exceptions, title: "Paginate the grouped case list", slot: Slot(0, .tue, 13, 30), reviewers: ["aisha"], project: exceptions,
               outcome: .prod, additions: 112, deletions: 28,
               body: "Cursor pagination, 50 cases a page. The biggest store queue is 1,400 cases."),
        DemoPR(repo: .promoRules, title: "Drop the unused rule_version column", slot: Slot(0, .tue, 17), reviewers: ["ben"],
               outcome: .prod, additions: 18, deletions: 46,
               body: "Superseded by the versions table in March. Nothing reads it."),
        DemoPR(repo: .stock, title: "Shadow mode: check stock live without changing baskets", slot: Slot(0, .wed, 10), reviewers: ["marcus", "priya"], project: liveStock,
               outcome: .staging, mergeAfterHours: 3, additions: 241, deletions: 22,
               body: "Checks a configurable share of baskets live, never changes them, and records agreement with what pickers found. Running at 5% in production."),
        DemoPR(repo: .promoRules, title: "Port rule 28: short-dated clearance prices per store", slot: Slot(0, .wed, 14, 30), reviewers: ["tomas"], project: promotions,
               outcome: .prod, additions: 189, deletions: 10,
               body: "Rule 28 on streaming. Backfill agreement 100%."),
        DemoPR(repo: .exceptions, title: "Enable errcheck and fix its 31 findings", slot: Slot(0, .wed, 17), reviewers: ["aisha"],
               outcome: .merged, mergeAfterHours: 16, additions: 94, deletions: 61,
               body: "Two of the 31 were real: a dropped error on note save, and one on refund draft export."),
        DemoPR(repo: .stock, title: "Fall back to the stock snapshot above 250ms", slot: Slot(0, .thu, 10, 30), reviewers: ["priya", "marcus"], project: liveStock,
               outcome: .open(.approved), additions: 158, deletions: 12,
               body: "When the live check misses the 250ms deadline, checkout uses the warehouse snapshot, the same as today. Every fallback is counted for the trading pack."),
        DemoPR(repo: .promoRules, title: "Port rule 29: no multibuys on HFSS products", slot: Slot(0, .thu, 13), reviewers: ["tomas", "grace"], project: promotions,
               outcome: .open(.changesRequested), additions: 222, deletions: 15,
               body: "Rule 29 on streaming. The HFSS list comes from the product catalogue feed.",
               notes: "Tomás wants the HFSS list refreshed daily rather than at deploy. Fair."),
        DemoPR(repo: .platform, title: "Fix a data race in the metrics batcher", slot: Slot(0, .thu, 16), reviewers: ["marcus"],
               outcome: .prod, mergeAfterHours: 2, additions: 19, deletions: 7,
               body: "Found by the race detector in the stock benchmark. Flush and append shared a slice without the lock."),
        DemoPR(repo: .stock, title: "Dashboard for shadow-mode agreement", slot: Slot(0, .fri, 9, 30), reviewers: ["marcus"], project: liveStock,
               outcome: .open(.reviewRequired), additions: 64, deletions: 0,
               body: "Agreement, disagreements by reason, p99 and fallback count, for Monday's architecture forum."),
        DemoPR(repo: .exceptions, title: "Stock history in the case side panel", slot: Slot(0, .fri, 13), project: exceptions,
               outcome: .draft, additions: 205, deletions: 6,
               body: "The SKU's last 7 days of stock movements next to the case, which shift leads asked for at the feedback session. Not in the MVP; parked as a draft."),
        DemoPR(repo: .promoRules, title: "Rename rule IDs to match the trading calendar", slot: Slot(0, .fri, 15), reviewers: ["tomas"],
               outcome: .open(.reviewRequired), additions: 120, deletions: 120,
               body: "Rule IDs now match the trading calendar Sam's team keeps, so prices and the calendar can be joined without a lookup table."),

        // Teammates
        DemoPR(repo: .promoRules, title: "Port rules 19 and 20: meal deal variants", slot: Slot(-2, .mon, 10), author: "tomas", reviewers: ["marcus"], project: promotions,
               outcome: .prod, additions: 344, deletions: 22,
               body: "Last two rules of the Q3 batch.", teammateOnly: true),
        DemoPR(repo: .platform, title: "Consumer lag alerts for fulfilment topics", slot: Slot(-2, .tue, 10), author: "marcus", reviewers: ["priya"],
               outcome: .prod, additions: 77, deletions: 5,
               body: "Alerts when any fulfilment consumer group is more than 10 minutes behind.",
               notes: "Approved. Suggested a separate threshold for the batch replay topic."),
        DemoPR(repo: .stock, title: "RFC: the stock ledger as a library shared with the picker app", slot: Slot(-2, .thu, 9), author: "priya", reviewers: ["marcus"],
               outcome: .merged, mergeAfterHours: 30, additions: 214, deletions: 0,
               body: "Proposes moving stock lookups into a shared library so checkout and the picker app agree on what's on the shelf.",
               notes: "Approved. Asked for a section on versioning, since a ledger change affects both teams at once."),
        DemoPR(repo: .exceptions, title: "Fix copy on the case header", slot: Slot(-2, .fri, 11), author: "ben", reviewers: ["aisha"],
               outcome: .prod, additions: 8, deletions: 8,
               body: "\"Exeption\" and two other typos the shift leads spotted."),
        DemoPR(repo: .stock, title: "Map multipacks to their single-unit stock", slot: Slot(-1, .mon, 9), author: "marcus", reviewers: ["priya"], project: liveStock,
               outcome: .prod, additions: 389, deletions: 41,
               body: "Counts a multipack against the single units it's made from. 18% fewer phantom out-of-stocks on the test set, no change to oversells. Behind a flag, with a rollback note.",
               notes: "Approved. Great description: benchmark numbers, flag and rollback plan."),
        DemoPR(repo: .promoRules, title: "Promotions DSL: sliding windows", slot: Slot(-1, .tue, 9, 30), author: "tomas", reviewers: ["priya"], project: promotions,
               outcome: .prod, mergeAfterHours: 30, additions: 467, deletions: 58,
               body: "Adds sliding windows to the DSL, so rules like 25 don't need hand-written state.",
               notes: "Requested changes first: window state wasn't checkpointed. Approved the second round."),
        DemoPR(repo: .exceptions, title: "Exception grouping heuristics: same SKU within 24 hours", slot: Slot(-1, .wed, 11), author: "aisha", reviewers: ["marcus"], project: exceptions,
               outcome: .prod, additions: 298, deletions: 19,
               body: "Groups exceptions on the same SKU, or the same order, within a configurable window.",
               notes: "Approved. Excellent tests. Suggested the window comes from config, which she did."),
        DemoPR(repo: .promoRules, title: "Unit tests for rule 24 edge cases", slot: Slot(-1, .wed, 14), author: "ben", reviewers: [], project: promotions,
               outcome: .prod, additions: 156, deletions: 3,
               body: "Baskets with a voucher applied, baskets edited after checkout, and baskets exactly at the threshold.",
               notes: "Approved. Good catch on the exactly-at-threshold case."),
        DemoPR(repo: .platform, title: "Idempotency middleware for fulfilment consumers", slot: Slot(-1, .thu, 14), author: "priya", reviewers: ["marcus"],
               outcome: .prod, mergeAfterHours: 24, additions: 231, deletions: 12,
               body: "INC-419 follow-up. Consumers declare an idempotency key per message type and the middleware drops repeats.",
               notes: "Approved. We should migrate the exceptions console onto it and drop my one-off fix."),
        DemoPR(repo: .stock, title: "Feature flag service integration for live stock", slot: Slot(0, .mon, 10), author: "priya", reviewers: ["marcus"], project: liveStock,
               outcome: .prod, additions: 66, deletions: 12,
               body: "Reads the shadow-mode percentage from the flag service so we can change it without a deploy.", teammateOnly: true),
        DemoPR(repo: .exceptions, title: "Shift notes on grouped cases", slot: Slot(0, .tue, 10), author: "aisha", reviewers: [], project: exceptions,
               outcome: .prod, additions: 187, deletions: 23,
               body: "UI for the notes API: add, edit and see who wrote what.",
               notes: "Approved."),
        DemoPR(repo: .promoRules, title: "Table-driven tests for the DSL parser", slot: Slot(0, .wed, 15), author: "ben", reviewers: [], project: promotions,
               outcome: .open(.changesRequested), additions: 241, deletions: 37,
               body: "Covers every DSL construct, including the new sliding windows.",
               notes: "Requested changes: test names describe the input rather than the behaviour."),
        DemoPR(repo: .promoRules, title: "Port rule 30: no alcohol multibuys in Scottish stores", slot: Slot(0, .wed, 16), author: "tomas", reviewers: [], project: promotions,
               outcome: .open(.reviewRequired), additions: 176, deletions: 8,
               body: "Rule 30 on streaming. Backfill agreement 99.8%; the difference is two products recategorised last month."),
        DemoPR(repo: .promoRules, title: "Loyalty streak backfill for the last 90 days", slot: Slot(0, .thu, 11), author: "marcus", reviewers: ["grace"], project: promotions,
               outcome: .open(.reviewRequired), additions: 128, deletions: 4,
               body: "Backfills the loyalty streak rule's state from the order log, so it doesn't start cold on deploy."),
        DemoPR(repo: .exceptions, title: "Fix timezone in the case SLA countdown", slot: Slot(0, .thu, 15), author: "aisha", reviewers: [], project: exceptions,
               outcome: .open(.reviewRequired), additions: 24, deletions: 9,
               body: "The countdown used UTC, so cases looked an hour more urgent during BST."),
        DemoPR(repo: .exceptions, title: "Empty state for shift leads with no assigned cases", slot: Slot(0, .fri, 10, 30), author: "ben", reviewers: ["aisha"], project: exceptions,
               outcome: .open(.reviewRequired), additions: 63, deletions: 2,
               body: "A friendly empty state with a link to the unassigned queue, instead of a blank table."),
    ]

    static let logEntries: [DemoLogEntry] = [
        DemoLogEntry(
            slot: Slot(-6, .mon, 9, 30), source: .manual, isPrivate: false, title: "Goals", tags: ["goals"],
            content: """
                ## H2 goals

                1. **Live stock at checkout.** Lead it from design to a 1% dark launch by the end of November, setting direction across checkout, store ops and fulfilment.
                2. **Promotions migration.** All 40 rules on the streaming engine by the end of Q4, and the nightly batch job deleted.
                3. **Operational excellence.** Fewer, better alerts. Every incident gets a postmortem with owned actions.
                4. **Grow the team.** Aisha ready for senior by mid-2027. Ben shipping a small project of his own.
                5. **Hiring.** Two or three interviews a week, scorecards in within a day.

                ## Staff signals I'm working towards

                - Sets technical direction beyond my own squad
                - Makes hard trade-offs explicit and gets them agreed
                - Raises the bar for others through review and mentoring
                - Leaves systems more operable than I found them
                """
        ),
        DemoLogEntry(
            slot: Slot(-2, .tue, 16, 30), source: .slack, title: "Decision: trust streaming over batch on orders around midnight",
            tags: ["decision", "promotions"], project: promotions,
            content: "The rule 22 backfill disagreed with batch on 0.3% of baskets. Every one was an order placed just before midnight that batch priced with the next day's promotions. Agreed in #fulfilment-eng to take the streaming result, and told trading why their numbers will shift slightly."
        ),
        DemoLogEntry(
            slot: Slot(-2, .wed, 12, 30), source: .slack, title: "INC-412: recalls checked against a 30-hour-old list",
            tags: ["incident", "recalls"], project: recalls,
            content: """
                **Status:** closed
                **Impact:** 14,212 orders were placed while the recall list was missing a day of additions. The re-check found no recalled products in any of them, so no customer impact.

                **Timeline**
                - Tue 02:10 nightly recall refresh hits a new column in the feed; the job logs a warning and exits 0
                - Wed 07:40 recall list age alert fires at 29 hours. I pick it up.
                - 08:05 incident declared; food safety and store ops told
                - 08:50 parser fixed and list refreshed
                - 11:30 re-check of affected orders complete: no hits

                **Root cause:** a parse failure was treated as a warning, and the list age alert sat at 24 hours.

                **Actions:** fail on format changes (done), alert at 6 hours (done), checksum downloads, a contract test against the feed format, a runbook.
                """
        ),
        DemoLogEntry(
            slot: Slot(-2, .thu, 17, 30), source: .manual, title: "Wrote the live stock design doc",
            tags: ["design", "live-stock"], project: liveStock,
            content: "Design for checking baskets against live dark store stock at checkout: the in-process ledger, the 150ms budget, the snapshot fallback above 250ms, shadow mode, and what store ops need to see. Reviewed today with Priya, Marcus, Grace and Sam; decisions are in the review notes."
        ),
        DemoLogEntry(
            slot: Slot(-2, .fri, 16, 30), source: .manual, isPrivate: false, title: "Weekly review", tags: ["weekly-review"],
            content: """
                **INC-412: stale recall list**
                **What:** Picked up the list age alert, led the incident, fixed the parser and re-checked 14,212 orders the same morning.
                **So what:** No recalled product reached a customer, and food safety heard it from us first. Turned the follow-ups into a project.
                **Evidence:** INC-412; the fail-loud parsing and list age alert PRs.
                **Goal:** Operational excellence
                **Signal:** Leaves systems more operable than I found them

                **Live stock design review**
                **What:** Wrote the design doc and ran the review with Priya, Marcus, Grace and Sam.
                **So what:** Architecture and fallback agreed in one meeting, with food safety on board from the start.
                **Evidence:** Design review notes, Thursday.
                **Goal:** Live stock at checkout
                **Signal:** Makes hard trade-offs explicit and gets them agreed

                ## Open threads
                - Ledger memory: Marcus worried about 1.2M rows
                - Ledger warm-up on pod start
                - Console feedback session with shift leads next Tuesday
                - Ben shadowing on-call next week

                ## Blind spots
                - PR reviews: about 6, not recorded
                """
        ),
        DemoLogEntry(
            slot: Slot(-1, .mon, 10, 30), source: .slack, title: "Helped search with phantom out-of-stocks",
            tags: ["help", "search"],
            content: "Search was hiding multipacks as out of stock when the single units were on the shelf. Pointed them at Marcus's multipack mapping and the shared stock library from Priya's RFC. They'll adopt the library next sprint instead of keeping their own stock cache."
        ),
        DemoLogEntry(
            slot: Slot(-1, .tue, 16), source: .slack, title: "INC-419: duplicate refund drafts in the exceptions console",
            tags: ["incident", "exceptions-console"], project: exceptions,
            content: """
                **Status:** closed
                **Impact:** 212 orders got a duplicate refund draft. No customer was refunded twice. About three hours of shift lead time went on spotting and setting aside duplicates.

                **Timeline**
                - 08:52 exceptions consumer redeployed; a rebalance replays 40 minutes of messages
                - 09:20 a shift lead reports two refund drafts on one order
                - 09:41 incident declared, consumer paused. I'm incident lead, Ben shadowing.
                - 10:15 root cause: refund draft creation had no idempotency key
                - 12:30 idempotency fix deployed
                - 15:30 Aisha's script merges the 212 duplicates; consumer resumed

                **Root cause:** at-least-once delivery met a non-idempotent write, and nothing alerted on the replay.

                **Actions:** idempotency key (done), shared idempotency middleware (Priya), replay alert (Marcus). Postmortem Thursday.
                """
        ),
        DemoLogEntry(
            slot: Slot(-1, .thu, 21), source: .manual, title: "Fulfilment social: bowling and pizza", tags: ["social", "team"],
            content: """
                Organised the team social at Strike & Slice in Shoreditch. 14 came: the whole squad, three of Owen's shift leads, Grace and Sam.

                - Two lanes, three games, pizza after
                - £21 a head against a £25 budget
                - A proper welcome for Ben, and the shift leads and engineers mixed far more than they do at work

                Next time: earlier in the month, and somewhere with a quiet corner for people who don't bowl.
                """
        ),
        DemoLogEntry(
            slot: Slot(-1, .fri, 16), source: .linear, title: "GRO-1203: 26 of 40 promotion rules on streaming",
            tags: ["promotions"], project: promotions,
            content: "Rules 21-26 moved this sprint. Backfill agreement is 99.7% or better on every rule, and every disagreement so far has been a batch bug. Rules 33 and 38 need cross-order joins; Tomás is scoping the DSL change."
        ),
        DemoLogEntry(
            slot: Slot(-1, .fri, 16, 45), source: .manual, title: "Recall feed hardening done",
            tags: ["recalls", "project"], project: recalls,
            content: "All five INC-412 follow-ups are in: fail-loud parsing, a 6-hour list age alert, checksums, a contract test against the feed format, and a runbook. Closed the project."
        ),
        DemoLogEntry(
            slot: Slot(-1, .fri, 17, 30), source: .manual, isPrivate: false, title: "Weekly review", tags: ["weekly-review"],
            content: """
                **INC-419: duplicate refund drafts**
                **What:** Incident lead. Contained it within an hour, shipped the idempotency fix by lunch, ran the postmortem on Thursday.
                **So what:** No customer refunded twice, and three hours of shift lead time lost instead of a day. Priya's shared middleware now stops the same bug in every consumer.
                **Evidence:** INC-419, the idempotency PR, postmortem notes.
                **Goal:** Operational excellence
                **Signal:** Leaves systems more operable than I found them

                **Shift lead feedback session for the exceptions console**
                **What:** Ran the session with Owen's shift leads and five real cases.
                **So what:** Cut the MVP to grouping plus notes, so shift leads get value about three weeks sooner.
                **Evidence:** Session notes, Tuesday.

                **Recall feed hardening**
                **What:** Landed all five INC-412 follow-ups and closed the project.
                **So what:** A feed format change now fails loudly within minutes, not silently for a day.
                **Goal:** Operational excellence

                ## Open threads
                - Shadow mode in production next sprint; the architecture forum needs the numbers
                - Rule 24 business-account threshold: Grace's analysis needs Sam's sign-off
                - Interview cap of 2 a week: Hannah talking to recruiting
                - Recall list age on the store dashboard: Owen has asked twice
                - Write the INC-419 actions into the incident doc

                ## Blind spots
                - PR reviews: about 8, for Marcus, Tomás, Ben and Priya
                """
        ),
        DemoLogEntry(
            slot: Slot(0, .mon, 9, 15), source: .manual, title: "On-call handover to Tomás", tags: ["on-call"],
            content: "Handed on-call to Tomás. The week had INC-419 and a noisy canary on the stock service that only fails in CI; muted it and filed a fix. Nothing else open."
        ),
        DemoLogEntry(
            slot: Slot(0, .tue, 12), source: .slack, title: "Explained the stock safety buffer to store ops",
            tags: ["ops", "live-stock"], project: liveStock,
            content: "Owen's shift leads asked why live stock holds back 2 units of every SKU. It's set from last year's pick data to keep oversells below 0.5%, and shadow mode will tell us whether the live check needs a different buffer. Pinned the answer in #fulfilment-ops."
        ),
        DemoLogEntry(
            slot: Slot(0, .wed, 17), source: .slack, title: "Shadow mode live on 5% of checkouts",
            tags: ["live-stock", "launch"], project: liveStock,
            content: "Live stock is running in shadow mode on 5% of checkouts. First six hours: 99.4% agreement with what pickers found, p99 112ms. The warehouse snapshot stays the source of truth."
        ),
        DemoLogEntry(
            slot: Slot(0, .thu, 12), source: .manual, title: "Wrote the live stock rollout plan",
            tags: ["live-stock", "doc"], project: liveStock,
            content: "One page for the product review: shadow at 5% for two weeks, a shift lead reviews every disagreement, then a 1% dark launch that removes out-of-stock items from real baskets, then 10%, 50% and 100% a week apart. Rollback is a flag flip back to the snapshot. Sent to Elena."
        ),
        DemoLogEntry(
            slot: Slot(0, .thu, 17, 30), source: .linear, title: "GRO-1221: snapshot fallback above 250ms",
            tags: ["live-stock"], project: liveStock,
            content: "PR approved. When the live check misses 250ms, checkout uses the warehouse snapshot, as today, and the fallback is counted for the trading pack. Merging Monday after the forum."
        ),
    ]
}
