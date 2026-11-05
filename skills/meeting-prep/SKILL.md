---
name: meeting-prep
description: Prepare for an upcoming meeting from Captain's Log. Picks a calendar event, creates its meeting, and writes short prep notes on what's open with the attendees and what's been closed since we last met. Use when I say prep, meeting prep, or prepare for a 1:1 or my next meeting.
argument-hint: "[meeting or person; defaults to offering upcoming events]"
allowed-tools:
  - Bash(captains-log status)
  - Bash(captains-log status *)
  - Bash(captains-log whoami)
  - Bash(captains-log whoami --pretty)
  - Bash(captains-log show *)
  - Bash(captains-log events list *)
  - Bash(captains-log meetings list *)
  - Bash(captains-log meetings add *)
  - Bash(captains-log todos list *)
  - Bash(jq *)
---

# Meeting prep

Get me ready to give an update: what's still open with these people, and what I've closed since we last talked. Load the `captains-log` skill first; its rules apply.

## 1. Pick the meeting

Run `events list` (today and the next week). Leave out interviews (`interviewID` set), all-day events and ones that have started. If I named a meeting or person, pick the match. Otherwise offer the next few as a choice.

If the event has a `meetingID`, `show` it. Otherwise `meetings add --event <id>`, which creates the meeting and prints the same as `show`:

- `attendees`
- `todos`, as the meeting's page lists them. `link` is `filed` (filed in this meeting), `tagged` (open, tagging an attendee) or `completedHere`.
- `previousMeetings`, newest first. `match` is `series` (an earlier instance of this recurring event) or `attendees` (mostly the same people).

## 2. Since last time

Take the newest previous meeting, preferring a `series` match. If there's none, skip to step 3.

- `show` it. Its notes and summary say what was discussed. Its `filed` todos are what we agreed then; each has `isCompleted`.
- `todos list --completed --from <its date> --person <id>`, with one `--person` per attendee other than me (`whoami`), for what I closed since.

A private meeting's text isn't printed; use its title and todos.

## 3. Prep notes

Draft terse bullets: one line each, no prose, nothing I'd have to skim. Name the person where it isn't obvious. Leave out empty sections, and keep the total under about ten bullets.

```
**Done since <day>**
- <todo or agreed item now closed>

**Open**
- <open todo>: <one-line status if the record says>

**Follow up**
- <something from last time's notes with no todo>
```

Show me the draft. Then, if the meeting's `prepNotes` is empty, save it with `meetings edit <id> --prep-notes -`. If it already has prep notes, ask whether to replace them, add below, or leave them. A private meeting's prep notes always read as empty, so for one of those, ask before saving.

If the previous meeting was private and this one isn't, ask whether to make this one private too (`meetings edit <id> --private`).
