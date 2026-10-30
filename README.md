# Captain's Log

A Mac app that keeps your work in one place. It pulls in your pull requests, review requests and calendar, and keeps your todos, meeting notes, interviews and feedback beside them. One look at the dashboard tells you what to do next, and at the end of the week Claude helps you write it up from what's there.

## What you get

- **One screen to start the day.** Today's meetings, your open PRs, the reviews waiting on you and today's todos. Click through to GitHub or the meeting; it doesn't try to replace them.
- **Notes that link up.** Tag a colleague in a todo and it shows on their page and in your next meeting with them. Their page gathers your feedback, PRs, meetings and interviews with them, which is most of what a performance review needs.
- **Your week, written up.** `/weekly-review` in Claude Code reads your week, asks you what mattered, and saves the answers as brag-doc entries. Ask "what did we decide about the migration?" and Claude answers from your own notes.

GitHub and your calendar sync on their own. Everything else you write here, so it pays off once it's where you keep your todos and take meeting notes. If those live in Things or Notion today, moving them is what it asks of you.

## Why I created this

Software shapes behaviour. Most of the software we use shapes it to suit its makers: we scroll more, click more, spend more. The flip side is that software you write for yourself can shape your behaviour to suit you.

I wanted one place that showed me everything I needed, so I'd stop checking three or four apps all day.

## How it's built

It comes in two parts over one local store: the Mac app and the CLI that Claude can interact with.

1. **A database underneath, Claude on top.** LLMs work quickly and cheaply if you give them the context they need and no more: that's exactly what the CLI does. "My overdue todos" or "everything linked to one person" is a query: it returns in milliseconds, gives the same answer every time, costs nothing, and stays that way as the store grows.
2. **A slick GUI with keyboard shortcuts.** All the information you need, instantly available. Adding or completing a todo and other common interactions are only a shortcut away.
3. **Native, not Electron.** An app that runs all day should cost next to no CPU or memory.

This is your tool, and you can customise it to suit your workflow. Fork it and change whatever you like (see [Make it yours](#make-it-yours)).

## Using it with Claude Code

Once the skills are installed, ask Claude things like:
- "What did I work on last week?"
- "What did Steve and I decide about the migration?"
- "What's on my plate today?"
- "Summarise this transcript and file it against today's 1:1 with Tom."

The `captains-log` skill answers from your store and nothing else. Read commands are pre-approved; anything that writes asks first. The `weekly-review` skill (`/weekly-review`) reads your week, interviews you about what mattered, and saves brag-doc entries back to the log.

The CLI works on its own too. Try `captains-log feed --pretty` for the past week, or `captains-log --help` for everything. [`docs/cli.md`](docs/cli.md) has the full reference.

## Install

[`docs/getting-started.md`](docs/getting-started.md) walks through all of this step by step, from a fresh Mac to your first weekly review.

## Reviewing the code

It reads your calendar and your GitHub activity, and you'll keep sensitive notes in it. So it promises little, and the promises are easy to check:

1. **It only reads.** It fetches from GitHub (through `gh`), Google Calendar (through `gws`). It never writes to any of them or acts on your behalf.
2. **The app calls no AI.** No LLM calls and no API spend. Claude sees your data only when you ask it something in Claude Code, which reads the store through the CLI.
3. **Your data stays on company hardware.** Everything lives in one SQLite file on your laptop. Backups go to your work Google Drive, encrypted so nobody else can read them. Nothing goes to iCloud.

Learn more in [`docs/security.md`](docs/security.md).

## Your data

- **Where it is:** `~/Library/Application Support/CaptainsLog/`, one SQLite file shared by the app and the CLI. `just data-info` shows it. macOS doesn't sync this folder to iCloud.
- **Backups:** once a day by default (Settings → Backups goes down to hourly) the app takes a consistent snapshot of the store (safe while it's running), compresses it and encrypts it with [age](https://age-encryption.org) into `~/Google Drive/My Drive/CaptainsLog backups/`, named by date and time. It keeps the newest 30 (change it in Settings). Back Up Now in Settings, or `just backup`, takes one now. A failing backup shows in the menu bar, and Claude mentions it when the last one is more than a week old.
- **Your passphrase is the only way back in.** Setting up backups encrypts the backup key with it. The key sits beside the backups, but it's useless without the passphrase. Forget the passphrase and every backup is unreadable.
- **Restoring:** run `just restore` in a terminal. It asks you to quit the app, lists your backups newest first, and asks for the passphrase. It checks the backup is sound before changing anything, then moves your current data aside to `CaptainsLog-before-restore-<time>` (next to the data folder) rather than deleting it.

## Make it yours

Fork it, then ask your Claude for the changes you want. [`CLAUDE.md`](CLAUDE.md) holds the architecture and the rules that keep the data safe, and Claude reads it first.

If you want to keep pulling in improvements and sending yours back, stay close to the architecture:
- **Shared core:** `Sources/CaptainsLogKit/` (models, store, sync, shared rules) and the CLI.
- **Yours to reshape:** the views, the dashboard, the interview flow.
- **Changing a model is the point of divergence.** Your store's schema then differs from everyone else's, which makes merging hard. For a new kind of record, a `LogEntry` with tags usually does the job.

If you build something others would want, open a PR. If you'd rather go your own way, that's fine too.

Before working on the code, read [`docs/overview.md`](docs/overview.md) (what works, what doesn't yet, known bugs). Run the tests with `just test` (needs `brew install xcbeautify`).
