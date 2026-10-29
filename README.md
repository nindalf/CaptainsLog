# Captain's Log

A Mac app that keeps your work in one place. It pulls in your pull requests, review requests and calendar, and keeps your todos, meeting notes, interviews and feedback beside them. One look at the dashboard tells you what to do next, and at the end of the week Claude helps you write it up from what's there.

## What you get

- **One screen to start the day.** Today's meetings, your open PRs, the reviews waiting on you and today's todos. Click through to GitHub or the meeting; it doesn't try to replace them.
- **Notes that link up.** Tag a colleague in a todo and it shows on their page and in your next meeting with them. Their page gathers your feedback, PRs, meetings and interviews with them, which is most of what a performance review needs.
- **Your week, written up.** `/weekly-review` in Claude Code reads your week, asks you what mattered, and saves the answers as brag-doc entries. Ask "what did we decide about the migration?" and Claude answers from your own notes.

GitHub and your calendar sync on their own. Everything else you write here, so it pays off once it's where you keep your todos and take meeting notes. If those live in Things or Notion today, moving them is what it asks of you.

## Why I created this

Software shapes behaviour. Most of the software we use shapes it to suit its makers: we scroll more, click more, spend more. The flip side is that software you write for yourself can shape your behaviour to suit you.

I wanted one place that showed me everything I needed, so I'd stop checking three or four apps all day. And I wanted writing performance reviews, for myself and others, to be easier.

## How it's built

It comes in three parts over one local store: the Mac app, a `captains-log` CLI that reads and writes everything the app shows as JSON, and Claude Code skills over the CLI.

1. **A database underneath, Claude on top.** People, meetings, todos and PRs are linked records in SQLite, not notes in text files. "My overdue todos" or "everything linked to one person" is a query: it returns in milliseconds, gives the same answer every time, costs nothing, and stays that way as the store grows. The dashboard tells you what to do next instantly without an LLM. Claude searching a folder of notes needs to read everything to find the ones that matter, and as the folder grows it can miss context. Here Claude does what it's good at, summarising and drafting your week, over data it didn't have to dig for.
2. **Native, not Electron.** An app that runs all day should cost next to no CPU or memory.
3. **Make it yours.** This is your tool, and you can customise it to suit your workflow. Fork it and change whatever you like (see [Make it yours](#make-it-yours)).

## Review it first

It reads your calendar and your GitHub activity, and you'll keep sensitive notes in it. So it promises little, and the promises are easy to check:

1. **It only reads.** It fetches from GitHub (through `gh`), Google Calendar (through `gws`). It never writes to any of them or acts on your behalf.
2. **The app calls no AI.** No LLM calls and no API spend. Claude sees your data only when you ask it something in Claude Code, which reads the store through the CLI.
3. **Your data stays on company hardware.** Everything lives in one SQLite file on your laptop. That's why this is a Mac app and not an iOS app syncing through iCloud: notes about the business don't go to Apple. Backups go to your work Google Drive, encrypted so nobody else can read them.
4. **You build it from source, after reviewing it.** There's no binary to download. Have your own Claude review the code, then build what you reviewed.

Don't take my word for any of it: point your Claude at the repo before you build it. [`docs/security.md`](docs/security.md) has the detail for a security review. The trust boundary is small:

- **Everything external goes through `runProcess`**, which runs `gh` and `gws` as subprocesses. Its call sites are in `Sources/CaptainsLogKit/Sync/` (`GitHubSync`, `CalendarSync`), and they only read: `gh pr list`, `gh pr view`, `gws calendar +agenda`, `gws calendar events list`.
- **There's no network code of its own** (no `URLSession`) and no LLM calls.
- **It writes to its own data directory**, `~/Library/Application Support/CaptainsLog/`. Settings go to UserDefaults, the app's `com.nindalf.captainslog` domain.
- **Once a day (or as often as hourly, in Settings) it writes an encrypted backup to your Google Drive folder**, `~/Google Drive/My Drive/CaptainsLog backups/`, and prunes old ones there. It does this by running `Sources/CaptainsLogKit/Backup/backup.sh` (`sqlite3`, `tar`, `age`) through `runProcess`. Backups are encrypted to a public key; the private key is in the same folder, encrypted with your passphrase.

A prompt to paste into Claude Code from the repo root:

```
Security-review this repo before I build and run it. It claims to only read
from GitHub (via gh) and Google Calendar (via gws), never write to any external
system, make no network calls of its own, call no LLMs, and write only to
~/Library/Application Support/CaptainsLog, its own UserDefaults, and age-encrypted
backups in ~/Google Drive/My Drive/CaptainsLog backups.
Verify each claim: find every subprocess, network call, file write and
credential access, in the app (captainslog/), the shared package
(Sources/CaptainsLogKit/), the CLI (Sources/captains-log/), the justfile and
scripts/. Report anything that contradicts the claims or surprises you.
```

## Install

[`docs/getting-started.md`](docs/getting-started.md) walks through all of this step by step, from a fresh Mac to your first weekly review.

## Using it with Claude Code

Once the skills are installed, ask Claude things like:
- "What did I work on last week?"
- "What did Steve and I decide about the migration?"
- "What's on my plate today?"
- "Summarise this transcript and file it against today's 1:1 with Tom."

The `captains-log` skill answers from your store and nothing else. Read commands are pre-approved; anything that writes asks first. The `weekly-review` skill (`/weekly-review`) reads your week, interviews you about what mattered, and saves brag-doc entries back to the log.

The CLI works on its own too. Try `captains-log feed --pretty` for the past week, or `captains-log --help` for everything. [`docs/cli.md`](docs/cli.md) has the full reference.

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

## Uninstall

```sh
pkill -x "Captain's Log"; sudo rm -rf "/Applications/Captain's Log.app"
rm /opt/homebrew/bin/captains-log
rm ~/.claude/skills/captains-log ~/.claude/skills/weekly-review
defaults delete com.nindalf.captainslog
rm -rf ~/Library/Application\ Support/CaptainsLog    # your data: back it up first
```

Your backups stay in `~/Google Drive/My Drive/CaptainsLog backups/`. Delete that folder too if you want them gone.
