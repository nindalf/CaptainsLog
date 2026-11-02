---
name: weekly-review
description: End-of-week review. Reads my week from Captain's Log, interviews me with pointed questions about what I did and why it mattered, then writes brag-doc entries mapped to my goals and saves them back to Captain's Log. Use when I say weekly review, brag doc, weekly writeup or Friday writeup.
disable-model-invocation: true
argument-hint: "[any day in the week to review; defaults to this week]"
allowed-tools:
  - Bash(captains-log status)
  - Bash(captains-log status *)
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

Turn a week in Captain's Log into brag-doc entries, by reading everything first and then interviewing me about it. Load the `captains-log` skill first: it covers the CLI, writing back, privacy and blind spots. Captain's Log is the only source: don't read git, GitHub, Slack or anything else. Where the store can't see something, ask me about it and record it as a blind spot (step 6).

## 1. Read the week

The week runs Monday to Sunday around the day given, or this week. Read all of it before asking anything.

- **Freshness:** `status`, as the `captains-log` skill describes. If anything didn't sync today, say so before the interview and offer `sync`.
- **Goals:** `log list --tag goals --from 2000-01-01`, then `show` the newest. It holds my goals and the progression framework signals I'm working towards. If there's none, ask me for them and save them with `log add "Goals" --tags goals --content -` before going on.
- **Last review:** `log list --tag weekly-review --from <five weeks back>`, then `show` the newest. Note its open threads: things in flight, blocked or promised.
- **The work:** `feed --from MON --to SUN`, then `show` every meeting and PR in it, and any log entry whose snippet isn't the whole story. Skip private records, interviews included: as the `captains-log` skill says, only their title, date and recommendation are yours to use.
- **Teammates' PRs:** `prs list --teammates --from MON --to SUN`, grouped by `author`.
- **Reviews:** `prs list --reviewed --from MON --to SUN`, a count, grouped by `author`. A PR counts once, in the week of my latest review of it.
- **People:** `people feedback list --from MON --to SUN`.
- **Unwritten meetings:** `events list --from MON --to SUN`. Events with no `meetingID` or `interviewID`, and meetings without notes, happened but left no record. That's normal: plenty of meetings don't need notes. Ask once whether anything came of them, and don't treat them as a gap.
- **Still open:** `prs list --mine --state open`, `todos list --overdue`, `todos list --list today`.

## 2. Plan the interview

Group what you read into a handful of threads: a project, a person, an incident, a decision. For each, note what the record already says and what it doesn't: why it mattered, what changed because of it, who else was involved, what the evidence is. Add last week's open threads, and the blind spots below, which the store can't see at all. Don't show me the plan; use it to ask good questions.

## 3. Interview

Ask one thing at a time and wait for the answer. Start with the thread that looks biggest. `references/questions.md` has question shapes; adapt them to the specifics instead of reading them out.

- Be pointed: name the meeting, PR or person. "The handover with Tom on Thursday: what does he own now that he didn't before?" rather than "How did the handover go?"
- Push past the first answer to impact and evidence. If I can't say why something mattered, ask once more, then move on.
- Always ask about the blind spots: reviews outside the configured repos, Slack threads, docs written, incidents, help given or received, decisions made outside meetings.
- For interviews and PR reviews, only the numbers matter: how many, and the hire/no-hire split. Take both from `interviews list` and `prs list --reviewed`, and don't debrief: no questions about content, scorecards, missing recommendations or mismatches. I'll ask explicitly if I want feedback on a scorecard.
- Keep asking "anything else?" until I say I'm done. The second and third things I mention are often the best.
- Don't summarise back after every answer; keep it moving.

## 4. Draft entries

One entry per achievement worth recording:

```
**[Date] — [One-line title]**
**What:** What I did, in 1-2 sentences.
**So what:** Why it mattered: business, team or technical impact.
**Evidence:** PR URLs, Slack links, meeting dates, metrics. Anything concrete.
**Goal:** Which of my goals it serves, if any.
**Signal:** Which framework signal it shows, if any.
```

- First person, in my words where possible. Specific beats impressive: "cut region launch from six weeks to two" beats "improved efficiency".
- Don't inflate, and don't force a goal or signal mapping that isn't there. Small weeks are fine.
- "So what" is the line that matters. If it's weak, ask rather than invent.
- Feedback I gave other people isn't an entry. Giving it is good practice, but it isn't my impact.

## 5. Review and save

Show me the entries and revise until I'm happy. Then save the review, after confirming:

```bash
captains-log log add "Weekly review: YYYY-MM-DD" --tags weekly-review --content - <<'EOF'
<the entries>

## Open threads
<what's in flight, blocked or promised, for next week's review to pick up>

## Blind spots
<what this review couldn't see in Captain's Log>
EOF
```

The date in the title is the week's Monday. If a review for that week already exists, `log edit` it rather than adding a second.

If the interview turned up facts that belong on a record (a meeting's outcome, a todo I committed to, feedback I gave), offer to file them with the `captains-log` skill's write commands.

Then go through the open threads without waiting to be asked. Read my open todos (`todos list --list` for inbox, today, upcoming and anytime). For each thread that's my own action and has no todo yet, propose one, with a project and a due date where the thread implies one. Where an existing todo already covers a thread, propose adding the detail to its notes instead. Create only the ones I pick. Threads that are other people's actions stay in the review for next week to pick up.

## 6. Blind spots

List every question you had to ask because the store couldn't answer it, and anything I mentioned that has no record. Group them by source (GitHub reviews, Slack, Linear, docs, unwritten meetings). For each kind that Captain's Log could capture, offer to record it as a potential gap in Captain's Log, as the `captains-log` skill describes, checking for an existing one first. Offer these separately from the open-thread todos in step 5, and don't call them todos.

Two things are never gaps: meetings without notes, and Slack. Slack will never be accessible to Captain's Log, so don't offer it as a gap or suggest getting access. Asking me about Slack threads in the interview is still fine.
