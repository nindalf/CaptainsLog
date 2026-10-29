---
name: captains-log
description: Read and update my work record (meetings and 1:1s, interviews, pull requests, todos, projects, people and feedback, log entries, calendar events) through the captains-log CLI. Use for any question about what I worked on, who I met, what was discussed or decided, what's on my plate, or to file notes, meeting summaries and todos.
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

# Captain's Log

`captains-log` is the CLI for my local work-tracking store, shared with the Captain's Log app. It is the only source to use: don't fill gaps from git, GitHub, Slack, Notion or the web. When the store can't answer, say so (see Blind spots).

## Reading

Every command prints JSON to stdout; pipe it through `jq`. Errors go to stderr with a non-zero exit. Every record carries an `id` (a UUID) to pass to the next command. Always name the `list` subcommand (`meetings list`, not `meetings`): the read commands are pre-approved by name, and writes ask first.

**Find, then read.** Lists and search are compact: titles, dates, flags, short snippets. `captains-log show <id>` prints one record of any type in full (notes, summary, transcript, PR body, every interview section) plus the ids of linked records (attendees, project, a todo's meeting). Read the full record before summarising or quoting it.

| Question | Start with |
|---|---|
| What did I do between two dates? | `feed --from D --to D` (log, meetings and interviews with notes, my PRs by merge date, completed todos) |
| Where did X come up? | `search "X"`; every word must match, across every type including people, projects and feedback; each hit has `type`, `matchedField` and a snippet |
| Meetings with someone | `people list --search NAME` to confirm who, then `meetings list --person NAME --from D` |
| Everything about a person | `show <person id>`: their feedback, meetings, interviews, PRs |
| Feedback given or received | `people feedback list --from D --to D` (`--person <id>`). Each item is feedback its person received: what I gave is on their page, what I got is on mine and says who it's from |
| What's on my plate | `todos list --list today` (or `inbox`, `upcoming`, `anytime`, `someday`), `prs list --mine --state open`, `prs list --reviews` |
| A project | `projects list`, then `show <project id>` |
| My calendar | `events list --from D --to D` (`--hidden` includes hidden events) |
| Interviews | `interviews list --from D`, `--candidate`, `--recommendation` |
| Log entries | `log list --from D --to D --tag T --source S` |

- Dates are `YYYY-MM-DD` in local time and `--to` includes that day. Lists default to the last week (events: the coming week), so pass `--from` when looking further back.
- Output timestamps are UTC. Convert to local time when presenting them.
- `captains-log <command> --help` lists every option.

## Writing

Write only when I've asked for it, or after proposing the exact change and getting a yes. Pass long text on stdin with `-` and a quoted heredoc, so nothing needs shell-quoting:

```bash
captains-log meetings edit <id> --summary - <<'EOF'
...
EOF
```

| To record | Use |
|---|---|
| A meeting summary or notes | `meetings edit <id> --summary -` (or `--notes`, `--prep-notes`, `--transcript`) |
| A standalone note, reflection or write-up | `log add "Title" --content - --tags a,b` (`--private` for reflections) |
| Something to do | `todos add "Title" [--due-date D] [--project NAME] [--notes -]` |
| Feedback for someone | `people feedback add <person id> -`. Feedback to me goes on my own person, starting `From <name>:` |
| Join up people from a roster file | `people import roster.json` previews the creates, merges, fills and conflicts; `--yes` applies them. `people export` prints a roster |
| Interview write-up | `interviews edit <id> --raw-notes -` (and `--upsides`, `--risk-factors`, `--conclusion`, `--recommendation`) |

- An empty value clears a field. `edit` commands change only the fields passed.
- Never run `delete --permanently`, `empty-trash`, `people merge --yes`, `people import --yes` or `projects complete --complete-todos` unless I asked for that specific action. Prefer `todos trash`, which is recoverable.
- Never run the `seed-*` commands, and never set `CAPTAINSLOG_STORE_DIR` unless I ask: it points the CLI at a different store.

## Privacy

Log entries, meetings, interviews and todos have `isPrivate`. Interviews and their todos are private by default, and so are todos filed from a private meeting; everything else isn't unless I mark it. Before putting store content anywhere others will read it (a Slack message, a doc, a PR), leave out private records. `edit` commands take `--private` / `--no-private`.

## Blind spots

The store holds only what sync brings in and what I write:

- GitHub: PRs I authored (the latest 50 per state in the configured repos), PRs whose review is requested from me personally (not my teams), and the open and merged PRs of teammates I sync (`people edit <id> --sync-prs`; `prs list --teammates`). Not reviews I've finished on other PRs, comments, or other repos.
- Calendar: allowlisted calendars, from when syncing started.
- Meetings and interviews: only what I wrote. One without notes is just a title, a time and attendees.
- Slack, Notion, Linear, documents and incidents: not ingested.
- Freshness: data is as of the last sync, which the app runs on a timer. See below.

## Freshness

Before answering a question about recent work, run `captains-log status`. For each source (`github`, `calendar`, `backup`) it gives `lastSuccess`, `syncedToday`, `isFailing` and the `lastError`.

- If the sources the answer relies on all have `syncedToday` true and `isFailing` false, say nothing about freshness.
- Otherwise add one short line naming the stale or failing source and when it last synced ("GitHub last synced Tuesday; the latest attempt failed: bad credentials"), so I know what the answer might be missing.
- `captains-log sync` refreshes GitHub and the calendar. Offer to run it when a source is stale; ask first.
- `backup` is the app's daily encrypted backup to Google Drive. Whenever you run `status`, check it: if it has no `lastSuccess`, or the last success is more than 7 days old, open your answer with one line saying so, with its `lastError`. If the error says there's no backup key, suggest Settings → Backups. Don't run backups yourself. To restore lost or broken data, I run `just restore` in a terminal (it needs my passphrase); suggest it, never run it.

## Reporting gaps

When an answer depends on one of the blind spots, say plainly what the store couldn't see rather than guessing or looking elsewhere. Then offer to record it as a **potential gap in Captain's Log**: something I might build into the app, as the person building it. When talking to me, call these "potential gaps in Captain's Log", never "todos" or "gap todos", and offer them separately from my real work todos so the two don't get mixed up. Under the hood each one is a todo: check `search "Captain's Log:"` for an existing one first, then `todos add "Captain's Log: <what's missing>" --notes -`, saying what question needed it.
