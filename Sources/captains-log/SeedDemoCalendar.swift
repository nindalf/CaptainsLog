import CaptainsLogKit

extension DemoSeeder {
    private static let squad = ["hannah", "priya", "marcus", "aisha", "tomas", "ben", "elena"]
    private static let rulesSync = ["priya", "grace", "marcus", "tomas"]

    static let meetings: [DemoMeeting] = [
        // Two weeks ago
        DemoMeeting(
            title: "Fulfilment sprint planning", slot: Slot(-2, .mon, 10, 30), minutes: 60, attendees: squad, location: "Fleet 3.04",
            notes: """
                Sprint 41 goals:
                - Promotions migration: rules 21-24 onto streaming (me, Tomás)
                - Live stock: design doc and latency baseline (me, Priya)
                - Exceptions console: grouping API spike (Aisha)

                Capacity is down a person: Marcus is on the warehouse vendor review most of the week. Ben picks up test coverage for the promotions engine, pairing with me on Thursdays.

                Elena flagged that store ops want grouped cases before anything else on the console.
                """
        ),
        DemoMeeting(
            title: "James / Elena 1:1", slot: Slot(-2, .mon, 15), attendees: ["elena"],
            prep: """
                - Console MVP scope
                - When do store ops need grouped cases?
                """,
            notes: """
                - Store ops want grouped cases before the end of November. Owen's shift leads are drowning in duplicate exceptions for the same SKU.
                - Elena wants to drop the stock history panel from the MVP. Agreed, as long as grouping ships with shift notes, otherwise context is lost at every shift handover.
                - She asked whether live stock will slow checkout down. Budget is 150ms p99, with a snapshot fallback above 250ms.
                - She'll take the cut-down scope to Owen on Thursday.
                """
        ),
        DemoMeeting(
            title: "James / Hannah 1:1", slot: Slot(-2, .tue, 11), attendees: ["hannah"],
            prep: """
                - Staff promo: which project is the flagship?
                - Interview load
                """,
            notes: """
                - Promo: Hannah thinks live stock is the right flagship. It crosses checkout, store ops and fulfilment, and she wants to see me set direction, not just build it.
                - Agreed I write the design doc myself and get Priya to challenge it rather than co-author.
                - Interviews are at 3 a week. Fine for now, but say something if it creeps up.
                - Ben is settling in well. Asks lots of questions, needs help scoping work.

                Actions:
                - Me: design doc draft by Thursday
                - Hannah: talk to the checkout EM about the latency budget
                """
        ),
        DemoMeeting(
            title: "Promotions migration sync", slot: Slot(-2, .wed, 11, 30), attendees: rulesSync, project: DemoProjects.promotions,
            notes: """
                Rules 21 and 22 are live on streaming. The backfill shows 100% agreement on 21 and 99.7% on 22: the gap is orders placed just before midnight, which batch priced with the next day's promotions. Streaming is right.

                Grace's customer segments are ready to feed rule 24. She wants a week of shadow data first.

                Tomás is blocked on rule 25 because the DSL has no sliding windows. He'll make it a DSL change rather than a one-off.
                """
        ),
        DemoMeeting(
            title: "James / Aisha 1:1", slot: Slot(-2, .wed, 14), attendees: ["aisha"],
            notes: """
                - Aisha wants to lead something end to end this half. The console grouping API fits: clear users, contained scope.
                - She's nervous about design reviews. Suggested a one-page note first, run past me before the wider review.
                - She asked how I knew to check recall list age first during INC-412 this morning. Walked her through the alert and the dashboard.
                """
        ),
        DemoMeeting(
            title: "James / Ben 1:1", slot: Slot(-2, .thu, 10), attendees: ["ben"],
            notes: """
                - First month: likes the team, finds the promotions engine codebase hard to navigate.
                - Paired on rule 23 tests for 40 minutes. He picked up the table-driven pattern quickly.
                - He'd like to shadow on-call. Asked Hannah to put him on next week's rota as shadow.
                """
        ),
        DemoMeeting(
            title: "Live stock at checkout: design review", slot: Slot(-2, .thu, 14), minutes: 60,
            attendees: ["priya", "marcus", "grace", "sam"], location: "Thames 2.11", project: DemoProjects.liveStock, recurring: false,
            prep: """
                - Latency budget
                - Fallback behaviour
                - What store ops and food safety need from shadow mode
                """,
            notes: """
                Decisions:
                - Check in-process against a stock ledger built from each dark store's pick and delivery events, seeded from the warehouse snapshot. No warehouse call on the checkout path.
                - Budget 150ms p99. Above 250ms checkout uses the snapshot, as it does today.
                - Shadow mode first: check live without changing baskets and compare with what pickers find, for two weeks.

                Sam: food safety is fine with the fallback as long as recall and age checks never depend on it, and every fallback is counted in the monthly trading pack.

                Marcus is worried about memory: every SKU in every dark store is about 1.2M rows. Benchmark before committing.

                Open: who owns ledger warm-up when a pod starts?
                """,
            summary: "In-process stock ledger with a snapshot fallback above 250ms, and two weeks of shadow mode first. Food safety wants fallbacks counted in the trading pack. Memory needs benchmarking."
        ),
        DemoMeeting(
            title: "James / Owen 1:1", slot: Slot(-2, .thu, 15, 30), attendees: ["owen"],
            notes: """
                - Shift leads handled 1,840 exceptions last week. About a third were the same SKU raised by two or more pickers.
                - INC-412: glad we told stores within the hour. He wants recall list age on the store dashboard so shift leads can see it themselves.
                - He'll bring three shift leads with real cases to a console feedback session next week.
                """
        ),
        DemoMeeting(
            title: "James / Priya 1:1", slot: Slot(-2, .fri, 11), attendees: ["priya"],
            notes: """
                - Her stock ledger RFC landed well. The picker app will use the same library for stock lookups.
                - She challenged the design doc on warm-up: a pod serving before the ledger loads would report everything out of stock. Adding a readiness probe that waits for the ledger.
                - She suggested I present live stock at the architecture forum myself. Booked for the first week of November.
                """
        ),

        // Last week
        DemoMeeting(
            title: "James / Hannah 1:1", slot: Slot(-1, .tue, 11), attendees: ["hannah"],
            prep: """
                - INC-419 so far
                - Social budget
                """,
            notes: """
                - INC-419 this morning: duplicate refund drafts. Contained by 10:15, cleanup underway with Aisha. Hannah takes comms with customer care.
                - She asked me to run the postmortem on Thursday.
                - Social: £25 a head. Approved bowling and pizza for Thursday.
                - Promo: write down the decisions from the design review, with who disagreed and why.
                """
        ),
        DemoMeeting(
            title: "Exceptions console: shift lead feedback session", slot: Slot(-1, .tue, 14), minutes: 60,
            attendees: ["owen", "elena", "aisha"], location: "Fleet 3.04", project: DemoProjects.exceptions, recurring: false,
            notes: """
                Owen brought three shift leads and five real cases.

                - The biggest time sink is opening the same SKU four times for four pickers' exceptions. Grouping by SKU is the top ask, by a distance.
                - Shift leads keep notes in a spreadsheet because the old tool drops them at handover.
                - Nobody uses the priority column. They want the SKU's recent stock movements instead.

                Agreed: the MVP is grouping by SKU and store within 24 hours, plus shift notes on the case. Aisha owns grouping, I own the notes API. The stock history panel stays out.
                """
        ),
        DemoMeeting(
            title: "Promotions migration sync", slot: Slot(-1, .wed, 11, 30), attendees: rulesSync, project: DemoProjects.promotions,
            notes: """
                Rules 23-25 are on streaming. Rule 25 uses Tomás's new sliding windows.

                Grace: business accounts clear the free delivery threshold on 90% of orders, four times the rate for households, so rule 24 gives away delivery on baskets that were never close. She'll propose a separate threshold for business accounts.

                26 of 40 by Friday looks likely. Rules 33 and 38 need cross-order joins, which the DSL can't do yet.
                """
        ),
        DemoMeeting(
            title: "James / Marcus 1:1", slot: Slot(-1, .wed, 16), attendees: ["marcus"],
            notes: """
                - Multipack mapping merged Monday: 18% fewer phantom out-of-stocks on the test set.
                - He wants the memory side of live stock. He takes the ledger benchmarking.
                - Frustrated the warehouse vendor review ate his whole week. He'll raise it with Hannah, and I'll back him at retro.
                """
        ),
        DemoMeeting(
            title: "James / Ben 1:1", slot: Slot(-1, .thu, 10), attendees: ["ben"],
            notes: """
                - He shadowed INC-419 and drove the comms updates in #fulfilment-incidents. Good instinct.
                - Paired on rule 26 tests. He found an off-by-one at the window boundary that I'd missed.
                - Next: the DSL parser tests on his own, with me reviewing.
                """
        ),
        DemoMeeting(
            title: "INC-419 postmortem: duplicate refund drafts", slot: Slot(-1, .thu, 11), minutes: 45,
            attendees: ["hannah", "aisha", "owen", "marcus", "tomas"], location: "Thames 2.11", project: DemoProjects.exceptions,
            recurring: false, key: "postmortem",
            notes: """
                Timeline:
                - 08:52 exceptions consumer redeployed; the rebalance replays 40 minutes of messages
                - 09:20 a shift lead reports duplicate refund drafts
                - 09:41 incident declared, consumer paused
                - 10:15 root cause: refund draft creation wasn't idempotent
                - 15:30 212 duplicates merged by script, consumer resumed

                No customer was refunded twice. About three hours of shift lead time lost.

                Actions:
                - Idempotency key on refund draft creation (me, done)
                - Shared idempotency middleware for every fulfilment consumer (Priya)
                - Alert when a consumer replays more than 5 minutes of messages (Marcus)
                - Write the actions into the incident doc (me)
                """,
            summary: "Replay plus a non-idempotent write. Idempotency fix shipped; shared middleware and a replay alert to follow."
        ),
        DemoMeeting(
            title: "Sprint 41 retro", slot: Slot(-1, .fri, 15), minutes: 45, attendees: squad, location: "Fleet 3.04", recurring: false,
            notes: """
                Went well:
                - Two incidents, both closed fast, with stores kept informed
                - 26 of 40 promotion rules on streaming
                - The shift lead session gave the console a clear MVP

                Didn't go well:
                - Marcus lost a week to the warehouse vendor review
                - Interviews: 3 a week each for me, Priya and Marcus
                - Stock CI takes 14 minutes

                Try next sprint:
                - Rotate the vendor review between seniors
                - Cap interviews at 2 a week each; Hannah to talk to recruiting
                """
        ),

        // This week
        DemoMeeting(
            title: "Fulfilment sprint planning", slot: Slot(0, .mon, 10, 30), minutes: 60, attendees: squad, location: "Fleet 3.04",
            notes: """
                Sprint 42 goals:
                - Live stock in shadow mode in production (me, Marcus)
                - Rules 27-32 onto streaming (me, Tomás)
                - Exceptions console: grouping and notes behind a flag (Aisha, me)

                Ben owns the DSL parser tests.

                Risk: the architecture forum is next Monday and needs shadow mode numbers.
                """
        ),
        DemoMeeting(
            title: "James / Elena 1:1", slot: Slot(0, .mon, 15), attendees: ["elena"],
            notes: """
                - Grouping is code complete behind a flag. Notes API this week.
                - She wants a demo for Owen's shift leads next Thursday. Agreed.
                - She needs the dark launch dates for the product review. I'll write a one-page rollout plan by Thursday.
                """
        ),
        DemoMeeting(
            title: "James / Hannah 1:1", slot: Slot(0, .tue, 11), attendees: ["hannah"], key: "hannah",
            prep: """
                - Promo evidence doc
                - Interview cap
                """,
            notes: """
                - Promo: the evidence doc is in good shape. Hannah wants one more example of influence outside the team; the architecture forum could be it.
                - Recruiting agreed to 2 interviews a week per senior, from next week.
                - She wants Ben to have a small project of his own next quarter. Suggested the console's empty states.
                - She's out Thursday and Friday.
                """
        ),
        DemoMeeting(
            title: "James / Grace 1:1", slot: Slot(0, .tue, 15), attendees: ["grace"],
            notes: """
                - Her basket analysis: business accounts order four times as often as households, and 90% of their baskets clear the free delivery threshold without trying.
                - Proposal: a higher rule 24 threshold for business accounts. Sam has to sign off, since it changes delivery pricing.
                - She'd like to try per-store demand forecasting next quarter. Interesting, but not before the migration is done.
                """
        ),
        DemoMeeting(
            title: "Promotions migration sync", slot: Slot(0, .wed, 11, 30), attendees: rulesSync, project: DemoProjects.promotions,
            notes: """
                Rules 27 and 28 are on streaming; 29 is in review. Tomás has rule 30 up, and 31 and 32 start next week.

                Agreed to delete the batch job only once rule 40 is live with two weeks of agreement data.
                """
        ),
        DemoMeeting(
            title: "James / Aisha 1:1", slot: Slot(0, .wed, 14), attendees: ["aisha"],
            notes: """
                - Grouping is behind a flag in production. Clean demo, and the 24-hour window is configurable.
                - She ran her design note past two shift leads before writing code this time.
                - She asked about promotion to senior. Talked through the gap: leading cross-team work, and writing for readers outside engineering.
                - She presents grouping at the ops demo next Thursday.
                """
        ),
        DemoMeeting(
            title: "Fulfilment x Trading monthly", slot: Slot(0, .wed, 16), minutes: 45, attendees: ["sam", "elena", "hannah"], location: "Thames 2.11",
            notes: """
                - Sam is happy with shadow mode, as long as the warehouse snapshot stays the source of truth until the dark launch.
                - Rule 24 business threshold: Sam wants Grace's analysis written up for the November trading committee.
                - The annual food safety audit is in December and needs recall response times.
                """
        ),
        DemoMeeting(
            title: "James / Ben 1:1", slot: Slot(0, .thu, 10), attendees: ["ben"],
            notes: """
                - His parser tests PR is up. Requested changes: the test names describe the input, not the behaviour.
                - He'd like more of the why behind design choices. Fair. I'll walk him through the live stock trade-offs next week.
                - Talked about the console empty states as his first project.
                """
        ),
        DemoMeeting(
            title: "James / Owen 1:1", slot: Slot(0, .thu, 15, 30), attendees: ["owen"],
            notes: """
                - Wrong-price exceptions are down 9% since rules 21-26 moved to streaming: shelf prices and app prices now change together.
                - He wants grouped cases on for his shift leads by mid-November. Demo next Thursday, then decide.
                - Asked for recall list age on the store dashboard again. Still not done.
                """
        ),
        DemoMeeting(
            title: "Live stock: shadow mode check-in", slot: Slot(0, .fri, 11), attendees: ["priya", "marcus", "owen"],
            location: "Thames 2.11", project: DemoProjects.liveStock, recurring: false,
            notes: """
                Shadow mode has run on 5% of checkouts since Wednesday.

                - 99.4% agreement with what pickers found, against 96.1% for the snapshot. Most of the 0.6% are multipacks split in store, which the ledger still counts as packs; Marcus is checking the pack mapping.
                - p99 is 112ms against the 150ms budget. The fallback fired 14 times, all during one pod restart.
                - Owen wants a shift lead to review every disagreement before we go past 5%.

                Next: present the numbers at the architecture forum on Monday.
                """,
            summary: "99.4% agreement with pickers and 112ms p99 at 5%. Disagreements need shift lead review before going wider."
        ),

        // Next week
        DemoMeeting(
            title: "Architecture forum: live stock at checkout", slot: Slot(1, .mon, 11), minutes: 60,
            attendees: ["priya", "marcus", "hannah"], location: "Auditorium", project: DemoProjects.liveStock, recurring: false, key: "forum",
            prep: """
                - Problem: checkout trusts a stock snapshot up to 30 minutes old
                - Design: in-process stock ledger, 150ms budget, snapshot fallback
                - Shadow mode: agreement, p99, fallback count
                - Ask: checkout agree the latency budget
                """
        ),
        DemoMeeting(
            title: "James / Hannah 1:1", slot: Slot(1, .tue, 11), attendees: ["hannah"],
            prep: """
                - How the forum went
                - Q4 goals draft
                - Ben's project next quarter
                """
        ),
        DemoMeeting(title: "Promotions migration sync", slot: Slot(1, .wed, 11, 30), attendees: rulesSync, project: DemoProjects.promotions),
        DemoMeeting(
            title: "James / Ben 1:1", slot: Slot(1, .thu, 10), attendees: ["ben"],
            prep: "- Walk through the live stock trade-offs he asked about"
        ),
        DemoMeeting(
            title: "Exceptions console: demo for store ops", slot: Slot(1, .thu, 14), minutes: 45,
            attendees: ["owen", "elena", "aisha"], location: "Fleet 3.04", project: DemoProjects.exceptions, recurring: false
        ),
        DemoMeeting(title: "James / Priya 1:1", slot: Slot(1, .fri, 11), attendees: ["priya"]),
        DemoMeeting(title: "Sprint 42 retro", slot: Slot(1, .fri, 15), minutes: 45, attendees: squad, location: "Fleet 3.04", recurring: false),
    ]

    static let interviews: [DemoInterview] = [
        DemoInterview(
            candidate: "Daniel Mensah", role: "Senior Software Engineer", format: "Systems Design", slot: Slot(-2, .tue, 14), coInterviewer: "marcus",
            scorecard: DemoScorecard(
                problem: "Delivery slot booking service",
                rawNotes: """
                    C Asked whether a slot is held when the basket opens or at checkout. Good start.
                    + API, booking workers and a van capacity store sketched in the first 10 minutes
                    + Raised double bookings from retried requests unprompted
                    Q What happens if the capacity store is slow?
                    + Timeout plus showing fewer slots, and said that trade-off needs an ops owner
                    ? A while on database choice before the shape was clear
                    H Nudged towards the Sunday evening peak
                    + Pre-computing capacity per van shift, refreshed as orders land
                    x Light on how stores and drivers would see a slot change
                    """,
                upsides: """
                    - _Reasons about tradeoffs_
                    - _Reasons effectively about edge cases & partial failure_
                    - _Asked clarifying questions_

                    Strong on failure modes: timeouts, retries, a degraded mode with an owner.
                    """,
                risks: "- Visibility for store ops was an afterthought.",
                level: "Senior. Could own a service like this.",
                recommendation: .yes,
                conclusion: "Hire. Would fit well on the live stock work.",
                debrief: "Marcus also a yes. Moving to offer."
            )
        ),
        DemoInterview(
            candidate: "Chloe Martin", role: "Software Engineer", format: "Pair Programming", slot: Slot(-2, .thu, 11), coInterviewer: "tomas",
            scorecard: DemoScorecard(
                problem: "Product search matcher",
                rawNotes: """
                    C Asked what counts as a match. Good.
                    + Started with exact matching and tests, then normalised case and whitespace
                    x Stuck on accents (jalapeño, crème fraîche), didn't look anything up
                    H Suggested Unicode normalisation
                    + Picked it up quickly once hinted
                    ? Rewrote the matcher twice instead of extending it
                    x No tests for synonyms like courgette and zucchini
                    x Ran out of time before fuzzy matching
                    """,
                upsides: """
                    - _Asked clarifying questions_

                    Good test-first habit at the start.
                    """,
                risks: """
                    - _Did not arrive at a working solution_
                    - _Did not make independent progress_
                    """,
                level: "Below the bar for engineer; a strong graduate.",
                recommendation: .no,
                conclusion: "No hire for this role. Worth suggesting the graduate scheme.",
                debrief: "Tomás agreed. Recruiting will suggest the graduate scheme."
            )
        ),
        DemoInterview(
            candidate: "Ravi Iyer", role: "Senior Software Engineer", format: "Systems Design", slot: Slot(-1, .mon, 14), coInterviewer: "priya",
            scorecard: DemoScorecard(
                problem: "Promotions pricing pipeline",
                rawNotes: """
                    C Asked about volumes, latency, and how a price reaches both the app and the shelf edge
                    + Split rule evaluation from catalogue enrichment with a stream between them
                    + Brought up late events and promotions that start at midnight unprompted
                    + Backfill: replay baskets from the log, compare with batch, cut over per rule
                    Q How would you test a rule change safely?
                    + Shadow rules writing to a separate topic, diff the prices daily
                    ? Short tangent on exactly-once delivery
                    + Clear about what he didn't know about pricing law, and asked
                    """,
                upsides: """
                    - _Is able to reason from first principles_
                    - _Reasons about tradeoffs_
                    - _Focuses on the core problem_

                    Proposed essentially the migration plan we're running, in 40 minutes.
                    """,
                risks: "- Little people leadership so far.",
                level: "Strong senior, staff-level on technical scope.",
                recommendation: .strongYes,
                conclusion: "Strong hire. Push for him.",
                debrief: "Priya also a strong yes. Offer out this week."
            )
        ),
        DemoInterview(
            candidate: "Lucy Hughes", role: "Software Engineer", format: "Pair Programming", slot: Slot(-1, .wed, 10), coInterviewer: "aisha",
            scorecard: DemoScorecard(
                problem: "Rate limiter",
                rawNotes: """
                    C Asked whether limits are per customer or per API key
                    + Fixed window with tests, then sliding window when asked about bursts
                    + Talked through her changes as she went
                    H Pointed at the injectable clock
                    + Used it straight away; the tests got simpler
                    x Didn't consider concurrent requests until asked
                    + Added a lock and a test that hammers it
                    """,
                upsides: """
                    - _Works iteratively and is unafraid to make changes_
                    - _Arrives at a working solution_
                    """,
                risks: "- _Did not reason effectively about edge cases & partial failure_",
                level: "Solid engineer.",
                recommendation: .yes,
                conclusion: "Hire.",
                debrief: "Aisha a yes too. Her first co-run interview, and her notes were great."
            )
        ),
        DemoInterview(
            candidate: "Kwame Asante", role: "Staff Engineer", format: "Systems Design", slot: Slot(-1, .fri, 10), coInterviewer: "priya",
            scorecard: DemoScorecard(
                problem: "Picker exception system",
                rawNotes: """
                    x Didn't ask who the users were
                    + Clean domain model: exception, case, order, refund
                    x Deep on service boundaries before the basic flow worked
                    Q How does a shift lead hand over a case?
                    x Hadn't thought about it; added a field
                    ? 15 minutes on the choice of message broker
                    + Excellent on audit trails and immutability
                    x Didn't reach refunds, which matter a lot here
                    """,
                upsides: """
                    - _Reasons about tradeoffs_

                    The audit trail answer was the best I've heard.
                    """,
                risks: """
                    - _Did not focus on the core problem_
                    - _Did not ask clarifying questions_

                    Designed for the architecture, not the shift leads.
                    """,
                level: "Senior, not staff.",
                recommendation: .no,
                conclusion: "No hire at staff. Possibly a yes at senior, if he's open to it.",
                debrief: "Priya leaned yes at senior. Recruiting will ask whether he'd consider it."
            )
        ),
        DemoInterview(
            candidate: "Sofia Rossi", role: "Senior Software Engineer", format: "Pair Programming", slot: Slot(0, .mon, 14), coInterviewer: "marcus",
            scorecard: DemoScorecard(
                problem: "Product search matcher",
                rawNotes: """
                    C Asked what a wrong match costs against a missed one. Great question for groceries.
                    + Normalised Unicode first, no hint needed
                    + Token-based matching so word order doesn't matter
                    + Tests for synonyms and brand names
                    ? Levenshtein on whole names, then switched to per token
                    x Match threshold was a magic number
                    + Explained how she'd set it from search click data
                    """,
                upsides: """
                    - _Is able to reason from first principles_
                    - _Arrives at a working solution_
                    - _Makes independent progress_
                    """,
                risks: "- Quick to code before settling the scoring approach.",
                level: "Senior.",
                recommendation: .yes,
                conclusion: "Hire.",
                debrief: "Marcus a strong yes. Going to offer."
            )
        ),
        DemoInterview(
            candidate: "Nadia Haddad", role: "Senior Software Engineer", format: "Systems Design", slot: Slot(0, .tue, 16), coInterviewer: "ben",
            scorecard: DemoScorecard(
                problem: "Delivery slot booking service",
                rawNotes: """
                    C Asked about the latency budget
                    + Clear API design and diagrams
                    x No answer for the capacity store being down
                    H Asked about timeouts
                    x Suggested retrying until it succeeds, on the checkout path
                    ? Long detour into autoscaling
                    + Good instincts on monitoring and alerting
                    """,
                upsides: """
                    - _Asked clarifying questions_

                    Strong on monitoring.
                    """,
                risks: """
                    - _Did not reason effectively about edge cases & partial failure_
                    - _Did not focus on the core problem_
                    """,
                level: "Mid-level on this evidence.",
                recommendation: .no,
                conclusion: "No hire for senior.",
                debrief: "Ben shadowed; his notes matched mine. A good first shadow."
            )
        ),
        DemoInterview(
            candidate: "Oliver Grant", role: "Senior Software Engineer", format: "Systems Design", slot: Slot(0, .thu, 14), coInterviewer: "tomas",
            scorecard: DemoScorecard(
                problem: "Promotions pricing pipeline",
                rawNotes: """
                    C Asked how fast a promotion must go live, and what pricing law expects
                    + Streaming design with per-rule state and a clear backfill story
                    + Raised the cost of a wrong price at the door unprompted
                    Q How do you roll out a new rule?
                    + Shadow topic, compare, then a flag per rule
                    x Hand-waved state recovery after a crash
                    H Asked about snapshots
                    + Got to checkpointing with the nudge
                    """,
                upsides: """
                    - _Reasons about tradeoffs_
                    - _Focuses on the core problem_
                    - _Works iteratively and is unafraid to make changes_
                    """,
                risks: "- State recovery needed a hint.",
                level: "Senior.",
                recommendation: .yes,
                conclusion: "Hire.",
                debrief: "Tomás a yes. The hiring manager wants a values interview next."
            )
        ),
        DemoInterview(candidate: "Hiro Tanaka", role: "Software Engineer", format: "Pair Programming", slot: Slot(1, .tue, 14), coInterviewer: "aisha"),
        DemoInterview(candidate: "Leo Fischer", role: "Staff Engineer", format: "Systems Design", slot: Slot(1, .wed, 16), coInterviewer: "priya"),
        DemoInterview(candidate: "Amara Obi", role: "Senior Software Engineer", format: "Systems Design", slot: Slot(1, .thu, 11), coInterviewer: "marcus"),
    ]
}
