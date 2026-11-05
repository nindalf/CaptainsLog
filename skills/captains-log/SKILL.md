---
name: captains-log
description: Read and update my work record (meetings and 1:1s, interviews, pull requests, todos, projects, people and feedback, log entries, calendar events) through the captains-log CLI. Use for any question about what I worked on, who I met, what was discussed or decided, what's on my plate, or to file notes, meeting summaries and todos.
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

# Captain's Log

`captains-log` reads and writes my local work store, the one the Captain's Log app uses. Use nothing else: not git, GitHub, Slack, Notion or the web. If the store can't answer, say so.

## Who I am

I'm in the store as a person like anyone else. Run `captains-log whoami` before reading people, attendees, feedback, transcripts or other people's notes. Leave `me` out of "who did I meet", and read my name in a transcript or someone's notes as "I". Person records also carry `isSelf`.

If `me` is null, ask which of the likeliest `candidates` I am, then run `captains-log whoami --set <id>`. If none of them is me, carry on and don't ask again this conversation.

## Reading

Output is JSON on stdout (pipe it through `jq`); errors go to stderr with a non-zero exit. Pass a record's `id` to the next command. Always spell out `list` (`meetings list`, not `meetings`): reads are pre-approved by name.

Lists and search are compact. `show <id>` prints any record in full, with the ids of linked records. Read it before summarising or quoting.

| Question | Start with |
|---|---|
| What did I do between two dates? | `feed --from D --to D`: log, meetings and interviews with notes, my merged PRs, completed todos |
| Where did X come up? | `search "X"` (every word must match, across every type) |
| Meetings with someone | `people list --search NAME`, then `meetings list --person NAME --from D` |
| A meeting | `show <meeting id>`: also its todos as the app lists them (`link` is `filed`, `tagged` with an attendee, or `completedHere`) and `previousMeetings` with the same people |
| Todos for someone | `todos list --person <id or name>` (repeatable); add `--completed --from D` for ones closed since |
| Everything about a person | `show <person id>` |
| Feedback | `people feedback list --from D --to D [--person <id>]`. Each item is feedback its person received: what I gave is on their page, what I got is on mine and says who from |
| What's on my plate | `todos list --list today` (or `inbox`, `upcoming`, `anytime`, `someday`), `prs list --mine --state open`, `prs list --reviews` |
| PRs I reviewed | `prs list --reviewed --from D --to D`, dated by my latest review |
| What teammates shipped | `prs list --teammates --from D --to D` |
| A project | `projects list`, then `show <id>` |
| My calendar | `events list --from D --to D` (`--hidden` for hidden events) |
| Interviews | `interviews list --from D` (`--candidate`, `--recommendation`) |
| Log entries | `log list --from D --to D --tag T --source S` |

- Dates are local `YYYY-MM-DD`, and `--to` is inclusive. Lists default to the last week (events: the next week).
- Output timestamps are UTC; show them in local time.
- `--help` on any command lists its options.

## Writing

Write only when I've asked, or after I've said yes to the exact change. Pass long text on stdin with `-` and a quoted heredoc:

```bash
captains-log meetings edit <id> --summary - <<'EOF'
...
EOF
```

| To record | Use |
|---|---|
| Meeting summary or notes | `meetings edit <id> --summary -` (or `--notes`, `--prep-notes`, `--transcript`) |
| A note, reflection or write-up | `log add "Title" --content - --tags a,b` (`--private` for reflections) |
| A todo | `todos add "Title" [--due-date D] [--project NAME] [--notes -]` |
| Feedback | `people feedback add <person id> -`. Feedback to me goes on my own person, starting `From <name>:` |
| Interview write-up | `interviews edit <id> --raw-notes -` (and `--upsides`, `--risk-factors`, `--conclusion`, `--recommendation`) |
| People from a roster file | `people import roster.json` previews the changes; `--yes` applies them. `people export` prints a roster |

- `edit` changes only the fields you pass; an empty value clears one.
- Run these only when I've asked for that exact action: `delete --permanently`, `prune --permanently`, `empty-trash`, `people merge --yes`, `people import --yes`, `projects complete --complete-todos`. Prefer `todos trash`, which can be undone.
- Never run `seed-*` commands or set `CAPTAINSLOG_STORE_DIR` (it switches stores) unless I ask.

## Privacy

Log entries, meetings, interviews and todos have `isPrivate` (`--private` / `--no-private` on `edit`). Interviews are private by default, as are todos filed from a private interview or meeting.

- The CLI never prints a private record's text (content, notes, summaries, interview write-ups), `show` included, and `search` matches only its title. You still get title, date, attendees, tags and an interview's recommendation, so you can count interviews and their hire/no-hire split, and write to a private record by id.
- If I ask what a private record says, tell me it's private and to open it in the app. Never make one public (`--no-private`) unless I ask for that.
- Leave private records out of anything others will read (Slack, docs, PRs).

## What the store can't see

The store has only what sync brings in and what I write.

- **GitHub**, configured repos only: my PRs (latest 50 per state); PRs asking me personally for review (not my teams); open and merged PRs of teammates I sync (`people edit <id> --sync-prs`); PRs I reviewed, if sync saw them within 30 days of their last update (only my latest review's date is kept). No comments.
- **Calendar:** allowlisted calendars, since syncing started.
- **Meetings and interviews:** only what I wrote. Without notes, one is just a title, a time and attendees.
- **Slack, Notion, Linear, documents, incidents:** not ingested.
- **Retention:** if it's on (Settings › Retention), old interviews lose their text but keep name, level and decision, and old calendar events without notes and old PRs are deleted. `captains-log prune` shows what the next run removes and `retentionDays` (null when off). A missing old record may have been pruned.

When an answer runs into one of these, say what the store couldn't see; don't guess or look elsewhere. Then offer to record it as a **potential gap in Captain's Log**: something I might build, as the app's author. Always call them that, never "todos", and offer them apart from my real todos. Each one is stored as a todo: check `search "Captain's Log:"` for an existing one, then `todos add "Captain's Log: <what's missing>" --notes -`, saying which question needed it.

## Freshness

Before answering about recent work, run `captains-log status`. Each source (`github`, `calendar`, `backup`) has `lastSuccess`, `syncedToday`, `isFailing` and `lastError`.

- If the sources you relied on synced today and aren't failing, don't mention freshness. Otherwise add one line naming the stale source and when it last synced ("GitHub last synced Tuesday; the latest attempt failed: bad credentials"), and offer to run `captains-log sync`.
- `backup` is the app's daily encrypted backup to Google Drive. If it has never succeeded, or last did more than 7 days ago, open your answer with one line saying so, with `lastError`; for a missing backup key, point me to Settings → Backups. Don't run backups. If data needs restoring, suggest I run `captains-log restore` in a terminal; never run it yourself.
