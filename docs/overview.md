# Overview

How the app fits together, and the decisions and rules that aren't obvious from the code. What's missing or broken is in the [issues](https://github.com/nindalf/CaptainsLog/issues), not here.

## Shape

- **CaptainsLogKit** (`Sources/CaptainsLogKit/`): models, store, sync, and every rule the app and CLI share. No UI frameworks.
- **App** (`captainslog/captainslog/`): SwiftUI, unsandboxed, single user.
- **CLI** (`Sources/captains-log/`): how Claude reaches the store. See `docs/cli.md`.
- **Skills** (`skills/`): `captains-log` (answer from the store), `weekly-review` (Friday interview into brag-doc entries) and `meeting-prep` (prep notes for an upcoming meeting; an upcoming meeting's page shows its command until a notes field is opened). Homebrew links them into `~/.claude/skills` and Codex's `~/.agents/skills` (`captains-log skills install`); `just install-skills` links a checkout's. `weekly-review/agents/openai.yaml` keeps Codex from running it unasked.
- **Store:** one SwiftData SQLite file (WAL) at `~/Library/Application Support/CaptainsLog/`, shared by app and CLI. `CAPTAINSLOG_STORE_DIR` points either at a scratch store, which never syncs. Versioned schema with a migration plan (`Schema.swift`); see the schema-change rules in CLAUDE.md. Expected scale after a year: a few thousand records per type, so query tuning doesn't matter.

## Conventions across the app

- **Dates** go through `DateLabel` (Kit): Yesterday/Today/Tomorrow, a weekday within this Monday-to-Sunday week, else "21 Oct", with the year only outside this year. Dates of things already done are picked with `DayField`.
- **Detail pages** (meeting, interview, person) are documents, not `Form`s (`DetailPage`): an editable title, a metadata line, boxed `DetailSection`s.
- **Content width:** lists and detail pages share one centred 760pt column (`contentColumn()`, inside the `ScrollView` so the scroller stays at the edge). Calendar and Dashboard fill the window. Tab lists are `ScrollView` + `LazyVStack` with `NavigationRow`, not `List`: a macOS `List` ignores `contentMargins`, and capping its frame moves its scroller into the window.
- **Card controls** end every editable card in the same order, bottom right: the record's pills or picker icons, then the privacy eye (`PrivacyEye`). No trash on cards: delete is in the context menu, on the open card as on its row, and the Delete key on a selected row. Only permanent deletes confirm; a todo goes to the Trash at once.
- **Navigation:** `Navigator` opens a linked record by pushing onto the current tab's stack, so Back returns to the link. Switching tabs clears the stack. Links still open a tab hidden in Settings.
- **Hiding a tab** in Settings › Sidebar hides its Dashboard panes too.

## Rules by area

- **Meetings** are made only from a calendar event's Add Notes; the calendar event owns the date. Deleting a meeting keeps its todos and event.
- **Interviews** come only from calendar sync, as stubs for events titled like an interview (`InterviewHeuristic`). They're private by default. Deleting one hides its calendar event, since sync would otherwise grow a new stub.
- **PR sync** (`GitHubSync`): repos are added and removed at the top of the Pull Requests tab, not in Settings, so a new user finds them where the PRs would be; `GitHubRepo.parse` takes a pasted link too. Adding one syncs at once. A PR is a review request (`isReviewRequest`) once requested, for good, even if a teammate fetch found it first. One only a teammate or reviewed-by-me fetch found is `isTeammateOnly`. Merged and closed fetches leave out `reviewDecision`, which times out. Any other PR still open locally is rechecked by number.
- **Calendar sync** (`CalendarSync`): timed events from the primary calendar; all-day events only from the allowlist; attendees linked only for events under 15 people. Every sync fetches the whole window (a week back to `calendarFetchWeeks` ahead), every page, and removes local events in it that Google didn't return. Google doesn't send a cancelled record for every deletion (an instance dropped from a recurring series, an interview pulled by the recruiting system), so absence is the only reliable signal: never go back to `updatedMin` or tombstones. A fetch cut short throws rather than reading as deletions. Declined events count as gone. An event moved out of the window is removed, and comes back as a new row when the window reaches it.
- **Setup** (`SetupCheck`): each source is not installed, not logged in, missing its scope, unconfigured or ready, rechecked before every sync and whenever the app comes to the front. A source that isn't ready skips its sync instead of recording a failure; its tab and the Dashboard checklist say the next step. `gh` counts as logged in from `gh auth token`, which reads the stored token without the network, so being offline never reads as logged out. `gws auth status` exits 0 either way: read its JSON.
- **Setup checklist** (Dashboard): new users are guided in the app, not a doc. Backups join once there's a todo, log entry or meeting to lose. The roster step counts done once anyone has a Slack handle, or both an email and a GitHub handle (sync only ever fills one); the review step once a log entry is tagged `weekly-review`. Both can be skipped (`skippedSetupSteps`); backups can't.
- **Sync loops:** each source runs its own `Task.sleep` loop in the app. Failures record per source in `SyncHistory` (`captains-log status`); GitHub saves what worked and reports the rest.
- **History pruning:** SwiftData's persistent history can't be switched off and nothing reads it, so the app's hourly loop deletes transactions older than 14 days (`HistoryPruner`). Only the app prunes.
- **Retention** (`Retention.swift`, Settings › Retention): per kind, on by default, 30 to 365 days. A setting stored in UserDefaults wins over the default, so an install that switched a rule off keeps it off. The app's hourly loop runs it after the backup; `captains-log prune` lists, or with `--permanently` removes. Interviews are cleared, not deleted (name, role, problem, level and decision stay), counting from the later of the interview and its debrief. Calendar events go only with no written meeting and no interview: clearing an interview can make it look like an empty stub. PRs go by `lastActivity` (GitHub's `updatedAt`), linked or not, and sync skips PRs older than the same cutoff, so they don't come back. `Todo.pullRequest` has no inverse, so `PullRequest.delete` unlinks todos by hand.
- **Search** (`Searcher`) is one engine for the app and CLI: every word must start a word somewhere in the record, ignoring case and diacritics.
- **People** pages list meaningful contacts only (linked to more than a calendar event). A roster import (`Roster`) matches by email, then GitHub, then Slack handle, and only fills empty fields. Every write path trims names, emails and handles (`Person.trimWhitespace`); the detail page binds keystroke by keystroke, so it trims on Return, focus loss and leaving the page (`onCommit`), never in the binding.
- **Who I am** is `Person.isSelf`, for Claude's sake: the app doesn't read it. It lives on the model rather than in settings so it survives a restore, a merge (`Person.absorb` carries it) and sandbox stores. `markAsSelf` keeps it to one person. Sync never sets it: `captains-log whoami` guesses from `isAuthoredByMe` PRs and calendar attendance, and the skill has Claude ask and run `whoami --set`.
- **Markdown editor** (`Views/Markdown/Native/`): a TextKit 1 `NSTextView` that restyles only the lines an edit touches (`MarkdownLineScanner`), and writes the model in bursts, before any click or command key.
- **Backups:** see `docs/security.md`. `age -p` only reads a terminal, so key creation runs it under `script(1)`; restore runs `age` through `runInteractiveProcess`, since `Process` puts children in a background process group that can't read the terminal.
- **Todos and projects:** `docs/todos.md`.

## Tests

Swift Testing in the app host (`just test`). Not covered: GitHub and calendar sync themselves (calendar's page decoding and `removeMissing` are), `Feed`, the CLI. The UI test target is template stubs.
