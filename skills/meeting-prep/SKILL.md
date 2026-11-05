---
name: meeting-prep
description: Prepare for an upcoming meeting from Captain's Log. Picks a calendar event, creates its meeting, and writes short prep notes on what's open with the attendees and what's been closed since we last met. Use when I say prep, meeting prep, or prepare for a 1:1 or my next meeting.
argument-hint: "[meeting or person; defaults to offering upcoming events]"
allowed-tools:
  - Bash(captains-log status)
  - Bash(captains-log whoami)
  - Bash(captains-log events list --upcoming --meetings)
  - Bash(captains-log meetings prep *)
---

# Meeting prep

Get me ready to give an update: what's still open with these people, and what I've closed since we last talked. Load the `captains-log` skill first; its rules apply.

## Commands

Run these, in order, and nothing else. Read the output as printed, without `jq`: lists print one record per line with keys in the same order, and times are local.

1. `captains-log status` and `captains-log whoami`, as the captains-log skill says.
2. `captains-log events list --upcoming --meetings`: meetings today and over the next week that haven't started, without interviews, all-day events or events with no one else. If I named a meeting or person, pick the match. Otherwise offer the next few as a choice.
3. `captains-log meetings prep <event id>`: makes the event's meeting if it has none, and prints everything the notes need:
   - `id` (the meeting's), `attendees`, `isPrivate`, and `prepNotes` if some are saved.
   - `todos`, as the meeting's page lists them. `link` is `filed` (filed here), `tagged` (open, tagging an attendee) or `completedHere`.
   - `lastMeetings`: the two latest earlier meetings, newest first, preferring the same series (`match`). Their `notes`, `summary` and `prepNotes` say what was discussed; their `todos` are what we agreed, each with `isCompleted`. Empty if there are none.
   - `completedSince`: todos closed since `since` that tag an attendee or are in a related project.
   - `relatedProjects`, and `projectTodos`: their open todos not already in `todos`.

   Every todo has `isOverdue` and its `notes`. A private meeting's text isn't printed; use titles and todos.
4. `captains-log meetings edit <meeting id> --prep-notes -`, once I've seen the draft (below).

## Prep notes

Draft terse bullets: one line each, no prose, nothing I'd have to skim. Name the person where it isn't obvious. Leave out empty sections, and keep the total under about ten bullets.

```
**Done since <the newest last meeting's day>**
- <from completedSince, or a lastMeetings todo now completed>

**Open**
- <from todos or projectTodos, overdue first>: <one-line status if its notes say>

**Follow up**
- <something in lastMeetings' notes or summary with no todo, not yet done>
```

Show me the draft. Then, if the meeting has no `prepNotes`, save it. If it has some, ask whether to replace them, add below, or leave them. A private meeting's prep notes are never printed, so for one of those, ask before saving.

If the newest of `lastMeetings` is private and this meeting isn't, ask whether to make this one private too (`meetings edit <id> --private`).
