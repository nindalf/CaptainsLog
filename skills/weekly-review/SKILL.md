---
name: weekly-review
description: End-of-week review. Reads my week from Captain's Log, interviews me with pointed questions about what I did and why it mattered, then writes brag-doc entries mapped to my goals and saves them back to Captain's Log. Use when I say weekly review, brag doc, weekly writeup or Friday writeup.
disable-model-invocation: true
argument-hint: "[any day in the week to review; defaults to this week]"
allowed-tools:
  - Bash(captains-log status)
  - Bash(captains-log status *)
  - Bash(captains-log whoami)
  - Bash(captains-log whoami --pretty)
  - Bash(captains-log show *)
  - Bash(captains-log search *)
  - Bash(captains-log feed *)
  - Bash(captains-log log list *)
  - Bash(captains-log meetings list *)
  - Bash(captains-log interviews list *)
  - Bash(captains-log prs list *)
  - Bash(captains-log todos list *)
  - Bash(captains-log projects list *)
  - Bash(captains-log people list *)
  - Bash(captains-log people feedback list *)
  - Bash(captains-log events list *)
  - Bash(jq *)
---

# Weekly review

Turn my week in Captain's Log into brag-doc entries: read everything, interview me, write it up. Load the `captains-log` skill first; its rules on sources, privacy, writing and gaps apply here.

## 1. Read the week

The week is Monday to Sunday around the given day (default: this week). Read all of it before asking anything.

- `status`. If anything didn't sync today, say so up front and offer `sync`.
- **Goals:** `log list --tag goals --from 2000-01-01`, then `show` the newest: my goals and the framework signals I'm working towards. If there are none, ask for them and save them with `log add "Goals" --tags goals --content -`.
- **Last review:** `log list --tag weekly-review --from <five weeks back>`, `show` the newest, and note its open threads.
- **The work:** `feed --from MON --to SUN`, then `show` every meeting and PR, and any log entry whose snippet looks cut short. Skip private records.
- **Teammates' PRs:** `prs list --teammates --from MON --to SUN`, grouped by `author`.
- **Reviews:** `prs list --reviewed --from MON --to SUN`, counted by `author`. A PR counts in the week of my latest review.
- **Feedback:** `people feedback list --from MON --to SUN`.
- **Calendar:** `events list --from MON --to SUN`. Events with no `meetingID` or `interviewID`, and meetings without notes, left no record. That's normal.
- **Still open:** `prs list --mine --state open`, `todos list --overdue`, `todos list --list today`.

## 2. Plan

Privately, group what you read into a few threads: a project, a person, an incident, a decision. For each, note what the record says and what's missing: why it mattered, what changed, who else was involved, the evidence. Add last week's open threads.

## 3. Interview

One question at a time; wait for the answer. Start with the biggest thread. Adapt the shapes in `references/questions.md` rather than reading them out.

- Be specific: "The handover with Tom on Thursday: what does he own now?", not "How did the handover go?"
- Push past the first answer to impact and evidence. If I can't say why it mattered, ask once more, then move on.
- Ask about what the store can't see: reviews outside the configured repos, Slack, docs, incidents, help given or received, decisions made outside meetings.
- Ask once whether anything came of the meetings that left no record.
- Interviews and PR reviews are just numbers: how many, and the hire/no-hire split, from `interviews list` and `prs list --reviewed`. Don't debrief them (content, scorecards, missing recommendations) unless I ask.
- Keep asking "anything else?" until I say I'm done; the later answers are often the best.
- Don't summarise each answer back.

## 4. Draft

One entry per achievement worth recording:

```
**[Date] — [One-line title]**
**What:** What I did, in 1-2 sentences.
**So what:** Why it mattered: business, team or technical impact.
**Evidence:** PR URLs, Slack links, meeting dates, metrics.
**Goal:** Which of my goals it serves, if any.
**Signal:** Which framework signal it shows, if any.
```

- First person, in my words where possible. Specific over impressive: "cut region launch from six weeks to two", not "improved efficiency".
- Don't inflate, or force a goal or signal. Small weeks are fine.
- If "So what" is weak, ask; don't invent.
- Feedback I gave others isn't an entry.

## 5. Save

Revise the entries with me until I'm happy, then save after confirming:

```bash
captains-log log add "Weekly review: YYYY-MM-DD" --tags weekly-review --content - <<'EOF'
<the entries>

## Open threads
<in flight, blocked or promised, for next week to pick up>

## Blind spots
<what this review couldn't see in Captain's Log>
EOF
```

Date the title with the week's Monday. If that week already has a review, `log edit` it instead.

Then offer follow-ups:

- **Records:** facts from the interview that belong on a record, such as a meeting's outcome or feedback I gave.
- **Todos:** read my open todos (`todos list --list` for inbox, today, upcoming and anytime). For each open thread that's my action and has no todo, propose one, with a project and due date where the thread implies them. Where a todo already covers a thread, propose adding to its notes. Create only the ones I pick. Other people's actions stay in the review.

## 6. Gaps

List what the store couldn't answer and anything I mentioned that has no record, grouped by source. For each kind Captain's Log could capture, offer a potential gap in Captain's Log (see the `captains-log` skill), separately from the todos above.

Meetings without notes and Slack are never gaps. Slack will never be accessible, so don't suggest it; asking me about Slack threads is still fine.
