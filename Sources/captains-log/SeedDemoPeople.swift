import CaptainsLogKit

extension DemoSeeder {
    static let projects: [DemoProject] = [
        DemoProject(
            name: DemoProjects.liveStock, icon: "cart",
            notes: """
                Check baskets against live dark store stock at checkout, instead of the warehouse snapshot exported every 30 minutes. Today about 4% of ordered items are out of stock at picking and become substitutions or refunds. Budget: 150ms p99 on checkout, snapshot fallback above 250ms.

                Shadow mode at 5% first, then a 1% dark launch, then 10%, 50%, 100% a week apart.
                """,
            completed: nil
        ),
        DemoProject(
            name: DemoProjects.promotions, icon: "gearshape",
            notes: """
                Move the 40 legacy promotion rules off the nightly SQL price batch onto the streaming pricing engine, so promotions go live in minutes rather than the next morning. Rules 1-20 moved in Q3.

                Rules 33 and 38 need cross-order joins in the DSL. The batch job goes once rule 40 has two weeks of agreement data.
                """,
            completed: nil
        ),
        DemoProject(
            name: DemoProjects.exceptions, icon: "magnifyingglass",
            notes: """
                Group related picker exceptions into one case and keep shift notes on it. Shift leads handle about 1,800 exceptions a week; the goal is 25% less handling time per case.

                MVP is grouping by SKU and store within 24 hours, plus notes. The stock history panel comes after.
                """,
            completed: nil
        ),
        DemoProject(
            name: DemoProjects.recalls, icon: "shield",
            notes: "Follow-ups from INC-412: fail loudly on format changes, alert on recall list age at 6 hours, checksum downloads, a contract test against the feed format, and a runbook.",
            completed: Slot(-1, .fri, 16, 45)
        ),
    ]

    static let people: [DemoPerson] = [
        // The user's own page: feedback they received, each item saying who it's from.
        DemoPerson(
            key: "kirk", name: "James Kirk", email: "james.kirk@larder.co.uk", github: nil, syncsPullRequests: false,
            feedback: [
                DemoFeedback(slot: Slot(-1, .thu, 13, 10), content: """
                    From Hannah:

                    > You ran INC-419 calmly and kept ops updated every 30 minutes without being asked. The postmortem draft was ready before the review, which made the meeting about actions rather than the timeline.
                    """),
                DemoFeedback(slot: Slot(-1, .fri, 9, 50), content: """
                    From Owen:

                    > Thanks for organising the social and making a point of inviting the shift leads. The stores really noticed.
                    """),
                DemoFeedback(slot: Slot(0, .tue, 9, 30), content: """
                    From Priya:

                    > The live stock design doc is the clearest I've reviewed this half. Next step: get the latency budget agreed with checkout before building more, so the fallback isn't a surprise to them.
                    """),
                DemoFeedback(slot: Slot(0, .thu, 10, 35), content: """
                    From Ben:

                    > The weekly pairing sessions are the most useful hour of my week. I'd like more of the why behind design choices, not just what they are.
                    """),
            ]
        ),
        DemoPerson(
            key: "hannah", name: "Hannah Okoye", email: "hannah.okoye@larder.co.uk", github: "hokoye", syncsPullRequests: false,
            feedback: [
                DemoFeedback(slot: Slot(-1, .fri, 17, 0), content: """
                    Thanks for taking the audit-prep requests off the team during the INC-419 week. Nobody got pulled off the cleanup, and it showed in how fast we closed it.
                    """),
            ]
        ),
        DemoPerson(
            key: "priya", name: "Priya Nair", email: "priya.nair@larder.co.uk", github: "priyanair", syncsPullRequests: true,
            feedback: [
                DemoFeedback(slot: Slot(-2, .fri, 12, 0), content: """
                    The stock ledger RFC made a hard call clearly: one library for checkout and the picker app, with the trade-offs written down. It made the live stock design much easier to argue for.
                    """),
            ]
        ),
        DemoPerson(
            key: "marcus", name: "Marcus Bell", email: "marcus.bell@larder.co.uk", github: "mbell", syncsPullRequests: true,
            feedback: [
                DemoFeedback(slot: Slot(-1, .tue, 17, 15), content: """
                    The multipack mapping PR was a model for a risky change: benchmark numbers in the description, a feature flag, and a rollback note. Exactly what a stock change needs.
                    """),
            ]
        ),
        DemoPerson(
            key: "aisha", name: "Aisha Rahman", email: "aisha.rahman@larder.co.uk", github: "aisharahman", syncsPullRequests: true,
            feedback: [
                DemoFeedback(slot: Slot(-1, .wed, 10, 0), content: """
                    You owned the refund draft cleanup script end to end during INC-419, and dry-ran it against a prod snapshot before touching anything. That's the judgement I'd expect from someone a level up.
                    """),
                DemoFeedback(slot: Slot(0, .wed, 14, 40), content: """
                    Running the grouping design note past two shift leads before writing code was exactly right. Next: take it to the wider design review yourself rather than through me.
                    """),
            ]
        ),
        DemoPerson(
            key: "tomas", name: "Tomás Silva", email: "tomas.silva@larder.co.uk", github: "tsilva", syncsPullRequests: true,
            feedback: [
                DemoFeedback(slot: Slot(-1, .thu, 16, 0), content: """
                    Sliding windows in the promotions DSL were a big unlock, and you took the review comments on board without fuss. The migration has sped up since.
                    """),
            ]
        ),
        DemoPerson(
            key: "ben", name: "Ben Carter", email: "ben.carter@larder.co.uk", github: "bencarter", syncsPullRequests: true,
            feedback: [
                DemoFeedback(slot: Slot(-1, .thu, 10, 40), content: """
                    Good first on-call shadow. You asked to drive the INC-419 comms updates, which was the right instinct. Next time, try writing the timeline yourself as it happens.
                    """),
            ]
        ),
        DemoPerson(
            key: "elena", name: "Elena Petrova", email: "elena.petrova@larder.co.uk", github: nil, syncsPullRequests: false,
            feedback: [
                DemoFeedback(slot: Slot(0, .mon, 15, 40), content: """
                    Cutting the exceptions console MVP down to grouping plus notes was the right call, and you sold it to ops well. Shift leads get value about three weeks sooner.
                    """),
            ]
        ),
        DemoPerson(
            key: "owen", name: "Owen Davies", email: "owen.davies@larder.co.uk", github: nil, syncsPullRequests: false,
            feedback: [
                DemoFeedback(slot: Slot(-1, .tue, 15, 15), content: """
                    The shift lead feedback session was the most useful hour we've had on the console. Bringing three shift leads with real cases beat any survey.
                    """),
            ]
        ),
        DemoPerson(
            key: "grace", name: "Grace Liu", email: "grace.liu@larder.co.uk", github: "graceliu", syncsPullRequests: false,
            feedback: [
                DemoFeedback(slot: Slot(0, .tue, 15, 45), content: """
                    The basket analysis for free delivery changed our minds on rule 24. Splitting it by customer type was the insight.
                    """),
            ]
        ),
        DemoPerson(
            key: "sam", name: "Sam Adeyemi", email: "sam.adeyemi@larder.co.uk", github: nil, syncsPullRequests: false,
            feedback: [
                DemoFeedback(slot: Slot(0, .wed, 17, 0), content: """
                    Really clear answers on the HFSS promotion rules. The one-page summary of what we can and can't discount has saved a lot of back and forth.
                    """),
            ]
        ),
    ]
}
