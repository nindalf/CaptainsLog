# Overview

How the app fits together, and the decisions and rules that aren't obvious from the code. What's missing or broken is in the [issues](https://github.com/nindalf/CaptainsLog/issues), not here.

## Shape

- **CaptainsLogKit** (`Sources/CaptainsLogKit/`): models, store, sync, and every rule the app and CLI share. No UI frameworks.
- **App** (`captainslog/captainslog/`): SwiftUI, unsandboxed, single user.
- **CLI** (`Sources/captains-log/`): how Claude reaches the store. See `docs/cli.md`.
- **Skills** (`skills/`): `captains-log` (answer from the store) and `weekly-review` (Friday interview into brag-doc entries). Homebrew links them into `~/.claude/skills` and Codex's `~/.agents/skills` (`captains-log skills install`); `just install-skills` links a checkout's. `weekly-review/agents/openai.yaml` keeps Codex from running it unasked.
- **Store:** one SwiftData SQLite file (WAL) at `~/Library/Application Support/CaptainsLog/`, shared by app and CLI. `CAPTAINSLOG_STORE_DIR` points either at a scratch store, which never syncs. Schema `CaptainsLogSchemaV1`, no migrations yet. Expected scale after a year: a few thousand records per type, so query tuning doesn't matter.

## Conventions across the app

- **Dates** go through `DateLabel` (Kit): Yesterday/Today/Tomorrow, a weekday within this Monday-to-Sunday week, else "21 Oct", with the year only outside this year. Dates of things already done are picked with `DayField`.
- **Detail pages** (meeting, interview, person) are documents, not `Form`s (`DetailPage`): an editable title, a metadata line, boxed `DetailSection`s.
- **Content width:** lists and detail pages share one centred 760pt column (`contentColumn()`, inside the `ScrollView` so the scroller stays at the edge). Calendar and Dashboard fill the window. Tab lists are `ScrollView` + `LazyVStack` with `NavigationRow`, not `List`: a macOS `List` ignores `contentMargins`, and capping its frame moves its scroller into the window.
- **Card controls** end every editable card in the same order, bottom right: the record's pills or picker icons, the privacy eye (`PrivacyEye`), the trash (`CardTrashButton`). The trash confirms only permanent deletes; a todo goes to the Trash at once.
- **Navigation:** `Navigator` opens a linked record by pushing onto the current tab's stack, so Back returns to the link. Switching tabs clears the stack. Links still open a tab hidden in Settings.
- **Hiding a tab** in Settings › Sidebar hides its Dashboard panes too.

## Rules by area

- **Meetings** are made only from a calendar event's Add Notes; the calendar event owns the date. Deleting a meeting keeps its todos and event.
- **Interviews** come only from calendar sync, as stubs for events titled like an interview (`InterviewHeuristic`). They're private by default. Deleting one hides its calendar event, since sync would otherwise grow a new stub.
- **PR sync** (`GitHubSync`): repos are added and removed at the top of the Pull Requests tab, not in Settings, so a new user finds them where the PRs would be; `GitHubRepo.parse` takes a pasted link too. Adding one syncs at once. A PR is a review request (`isReviewRequest`) once requested, for good, even if a teammate fetch found it first. One only a teammate or reviewed-by-me fetch found is `isTeammateOnly`. Merged and closed fetches leave out `reviewDecision`, which times out. Any other PR still open locally is rechecked by number.
- **Calendar sync** (`CalendarSync`): timed events from the primary calendar, incremental with a full fetch each Monday; all-day events only from the allowlist; attendees linked only for events under 15 people.
- **Setup** (`SetupCheck`): each source is not installed, not logged in, missing its scope, unconfigured or ready, rechecked before every sync and whenever the app comes to the front. A source that isn't ready skips its sync instead of recording a failure; its tab and the Dashboard checklist say the next step. `gh` counts as logged in from `gh auth token`, which reads the stored token without the network, so being offline never reads as logged out. `gws auth status` exits 0 either way: read its JSON.
- **Setup checklist** (Dashboard): new users are guided in the app, not a doc. Backups join once there's a todo, log entry or meeting to lose. The roster step counts done once anyone has a Slack handle, or both an email and a GitHub handle (sync only ever fills one); the review step once a log entry is tagged `weekly-review`. Both can be skipped (`skippedSetupSteps`); backups can't.
- **Sync loops:** each source runs its own `Task.sleep` loop in the app. Failures record per source in `SyncHistory` (`captains-log status`); GitHub saves what worked and reports the rest.
- **History pruning:** SwiftData's persistent history can't be switched off and nothing reads it, so the app's hourly loop deletes transactions older than 14 days (`HistoryPruner`). Only the app prunes.
- **Search** (`Searcher`) is one engine for the app and CLI: every word must start a word somewhere in the record, ignoring case and diacritics.
- **People** pages list meaningful contacts only (linked to more than a calendar event). A roster import (`Roster`) matches by email, then GitHub, then Slack handle, and only fills empty fields. Every write path trims names, emails and handles (`Person.trimWhitespace`); the detail page binds keystroke by keystroke, so it trims on Return, focus loss and leaving the page (`onCommit`), never in the binding.
- **Markdown editor** (`Views/Markdown/Native/`): a TextKit 1 `NSTextView` that restyles only the lines an edit touches (`MarkdownLineScanner`), and writes the model in bursts, before any click or command key.
- **Backups:** see `docs/security.md`. `age -p` only reads a terminal, so key creation runs it under `script(1)`; restore runs `age` through `runInteractiveProcess`, since `Process` puts children in a background process group that can't read the terminal.
- **Todos and projects:** `docs/todos.md`.

## Tests

Swift Testing in the app host (`just test`). Not covered: GitHub and calendar sync themselves, `Feed`, the CLI. The UI test target is template stubs.
