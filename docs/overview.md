# Captain's Log: what it does, and what it doesn't yet

A personal work log for one person: meetings, PRs, todos, interviews, people and notes in one local store, so the weekly write-up stops being hours of copying from Slack, GitHub, Notion and Calendar. A macOS app, a CLI over the same store, and Claude Code skills over the CLI. As of 2026-10-18.

## Shape

- **CaptainsLogKit** (`Sources/CaptainsLogKit/`): models, store, sync, and every rule the app and CLI share. No UI frameworks.
- **App** (`captainslog/captainslog/`): SwiftUI, unsandboxed, ad-hoc signed, single user.
- **CLI** (`Sources/captains-log/`): see `docs/cli.md`. Not yet: project icons.
- **Skills** (`skills/`): `captains-log` (answer questions from the store) and `weekly-review` (Friday interview into brag-doc entries). Installing with Homebrew, the recommended way, links them into `~/.claude/skills` and Codex's `~/.agents/skills` (`captains-log skills install`, from `homebrew/captains-log.rb`); `just install-skills` links a checkout's into `~/.claude/skills`. `weekly-review/agents/openai.yaml` keeps Codex from running it unasked. Untested in Codex.
- **Card controls:** log entries, todos (in Todos, the Log and Quick Entry), meetings and interviews end in the same controls at the bottom right: a record's pills or picker icons (project, When, tags), then an eye for `isPrivate` (crossed out when private; `PrivacyEye`), then a trash (`CardTrashButton`; detail pages keep both in the window toolbar). The trash confirms only permanent deletes; a todo goes to the Trash at once. Quick Entry has no trash, PRs no eye or trash. No highlight or flag.
- **Store:** one SwiftData SQLite file (WAL) at `~/Library/Application Support/CaptainsLog/`, shared by app and CLI. `CAPTAINSLOG_STORE_DIR` points either at a scratch store, which never syncs. Schema `CaptainsLogSchemaV1`, no migrations yet. Expected scale after a year: a few thousand records per type, tens of MB, so query tuning doesn't matter.

## By area

Each area: what works, then what doesn't yet. `Not yet` items are planned or wanted; `Bug` items are wrong today.

**Shell and menu bar** (`ContentView`, `Sidebar`, `Navigator`, `MenuBarView`, `SettingsView`)
- Dates everywhere go through `DateLabel` (Kit): Yesterday/Today/Tomorrow, a weekday for the rest of this Monday-to-Sunday week, else "21 Oct" with the year only outside this year. Day headers spell it out ("Wednesday 22 Oct"). Times only where they matter: meetings, interviews, the menu bar, the calendar, Log rows. Dates of things already done (debrief, feedback) are picked with `DayField`, which shares `MonthGrid` with the Todo When popover. Todos → Completed keeps an absolute date on every row, as Things' Logbook does. The Dashboard title is a stardate: year, day of the year, hour.
- Meeting, interview and person pages are documents, not `Form`s (`DetailPage`): a large editable title, a metadata line, then boxed `DetailSection`s that grow with their content.
- Tabs: Dashboard, Log, Calendar (`.meetings`), Pull Requests, Todos, Interviews, People, Search. Settings is its own window (Cmd-,) with four panes: General (Quick Entry, weekends), Sidebar, Sync, Backups. Menu bar: next event, counts of my PRs, reviews and today's todos, sync status or last error, Sync button.
- Settings → Sidebar orders the tabs (up and down buttons; grouped forms ignore drag) and hides any of them (`AppSettings.sidebarOrder` and `hiddenSidebarTabs`, by raw value; tabs missing from the order go last). Launch falls back to the first visible tab when the Dashboard is hidden. Links from elsewhere still open a hidden tab.
- Settings → Sync: GitHub and calendar intervals (5 and 10 min), repos and calendar allowlist (add with the button or Return, remove with the minus button or right-click), weeks to fetch (default 4).
- `Navigator` opens a person, meeting or interview from links elsewhere by pushing onto the current tab's stack, so Back returns to where the link was. Switching tabs clears the stack.
- Not yet: links to PRs or log entries.

**Dashboard** (`DashboardView`, `DashboardAgenda`, `Agenda`)
- An agenda: today's events as a list (past ones faded, the current one marked Now, all-day ones as chips), or, when today has none, the next day with any in the next two weeks. My PRs (open or undeployed, at most four), review requests, the Today list, and the log feed without completed todos, which Today already shows. Each pane is a light grey box, sized to its content; the last in each column (review requests, log) takes the rest and scrolls. Today stops growing at 360pt. Hiding a tab in Settings hides its panes (Calendar: the agenda; Pull Requests: both PR panes; Todos: Today; Log: the feed), and an emptied column goes, leaving the other the full width.
- Not yet: a "ready to ship" count.

**Log** (`LogListView`, `Log/LogListContent`, `Feed`)
- A merged feed by day: log entries, meetings with notes, interviews with raw notes, my PRs (dated by merge), completed todos (their checkbox reopens them, asking first for anything completed before today). Row snippets are plain text (`markdownPreview`); only non-manual sources get a badge. A type filter. Cmd+N adds an entry inline; entries edit in place, and so do completed todos (title, notes; the card shows when it was completed).
- Delete (key or right-click) removes a log entry, meeting or interview for good after a confirmation (`DeleteConfirmation`), and moves a completed todo to the Trash. PRs mirror GitHub, so they don't delete. Cards have a trash icon too.

**Meetings** (the Calendar tab: `MeetingListView`, `MeetingDetailView`)
- Calendar view (default) or a flat list; the choice is remembered. Detail: title, date (read-only; the calendar event owns it), attendees, Slack link, todos, prep notes, notes, summary. The todos are the ones filed against the meeting, then every open todo that tags an attendee, with the attendee's name under it, then the completed ones, including any checked off in this meeting.
- Meetings are made only from a calendar event's Add Notes. The page's trash button deletes one, keeping its todos and event.
- Not yet: editing transcript, project or tags (the CLI sets transcript); private notes; summarising a transcript.

**Calendar** (`Views/Calendar/`)
- Week grid with an all-day band (weekends optional), prev/next/today and arrow keys. An event opens its meeting or interview, or offers Add Notes, Hide or Delete.
- Not yet: unhiding an event (the CLI can).

**Pull requests** (`PRListView`)
- My PRs, review requests (no drafts) and teammates' PRs, older PRs behind a button (my deployed PRs; anyone else's merged more than five weekdays ago; closed), a state filter. Chips above list everyone whose PRs are synced, with counts: people synced by choice (marked, first) and review-request authors. Clicking one hides their PRs everywhere, the menu bar and Dashboard counts included (`AppSettings.hiddenPRAuthors`, by GitHub handle); right-click turns syncing all their PRs on or off. Card: status (draft, approved, staging, prod...), stats, body, people, notes, flag. Right-click a review request for "Add a Todo to Review": a todo for today titled "Review PR <title>" (clipped at 60 characters) with the PR's URL as notes, linked to the PR (`ReviewTodo`). Its row shows a GitHub mark that opens the PR.
- Not yet: markdown notes; incremental "show more".

**Todos and projects**: Things-style lists, projects, the Trash. Everything is in `docs/todos.md`, including its backlog.

**Interviews** (`InterviewListView`, `InterviewDetailView`, `ScorecardTodo`, `InterviewHeuristic`)
- List by month. Detail: candidate, problem, whiteboard, co-interviewer, todos, raw notes with copy-with-key, a scorecard (theme buttons, upsides, risks, level, recommendation), conclusion, debrief. The first note creates a "Submit scorecard" todo, once, private if the interview is.
- Calendar sync makes an interview stub for events titled like an interview, with candidate, role and a co-interviewer. That is the only way in: the app has no Add Interview, and the date is read-only.
- Private by default (the toolbar's eye). Delete from the page's trash button or a right-click in the list (`Interview.delete`). Its todos stay, and its calendar event is hidden, since sync would otherwise grow a new stub.
- Bug: the stub drops the `problemName` the title parser finds.
- Not yet: an upcoming/past split; an empty debrief date (the picker shows today).

**People and feedback** (`Views/People/`, `Person+Merge`)
- Meaningful contacts (linked to more than a calendar event), ranked by activity, searchable. Detail: profile, a "Sync all their PRs" toggle (needs a GitHub handle; syncs at once), open todos that tag them, feedback they received (add, edit, delete; feedback to the user goes on their own page and says who it's from), linked PRs, meetings, interviews, log entries that tag them. Merge folds a duplicate in.
- Rosters (`CaptainsLogKit/Roster`, `RosterSheets`): a JSON array of `{name, email, github, slack}`. The People toolbar's Roster menu imports one, previewing the new people, merges, filled fields and conflicts first, and exports one from a checklist that starts with the people whose PRs are synced. A row matches by email, then GitHub, then Slack handle, ignoring case, and folds several matches into the email match (`Person.absorb`). Only empty fields are filled, a placeholder name (a handle or an email's local part) counting as empty; a stored value that differs is kept and shown. A row matching someone an earlier row matched is skipped. The roster doesn't carry the sync-PRs flag. GitHub sync finds a person by login ignoring case, so a roster handle typed in lowercase isn't duplicated.

**Search** (`SearchView`, `CaptainsLogKit/Searcher`, `SearchMatch`)
- One engine for the app and the CLI. Every word must start a word somewhere in the record, ignoring case and diacritics. It searches meaningful people (name, email, handles), projects (name, notes), todos not in the Trash, log entries, meetings (title, prep notes, notes, summary, transcript), every interview section, PRs (title, body, notes, repo, number, author) and feedback (content, person).
- Results are one list, ordered undated first (people, open projects, undated todos), then newest first. Each row shows the matched words highlighted and, when the match isn't in the title, a snippet labelled with its field. A type filter has counts. Search runs on `Searcher`'s actor, 150 ms after typing stops. The query lives in `Navigator`, so it survives a trip to another tab.
- Log entries and PRs expand in place, using the cards from their own tabs. PRs have a GitHub button. Todos open on their home list, selected (`Navigator.openTodo`). Projects open in Todos; feedback opens its person. Return in the field selects the first result; arrows, Return and Escape work in the list.
- Not yet: log entry tags; meeting attendees (search the person instead); calendar events; ranking beyond date.

**Markdown fields** (`Views/Markdown/`, `CaptainsLogKit/Markdown/`)
- Live styling. `@` and `#` suggest people and PRs, in todo, log and Quick Entry titles too; a person inserts as their Slack handle. A tag in a todo or log entry links it to the person when its card closes (`MentionsPeople`, `docs/todos.md`); elsewhere tags are plain text. Typing `'s` or `' ` after a tag drops the space before it (`@alice's`). Copy for Slack (HTML plus markdown; blank lines become empty paragraphs, since Slack gives paragraphs no margin) and paste from Slack.
- The editor (`Native/`, behind `MarkdownEditor`) is a TextKit 1 `NSTextView` that restyles only the lines an edit touches, using `MarkdownLineScanner`. It draws clickable checkboxes, code blocks and quote bars, and shows suggestions at the caret. Return continues lists, Tab nests them, Cmd-B/I/K and Cmd-Shift-X format, and Cmd-click opens links. A space typed after a tag is taken back out before `'s` or `, . ? ! ;`, so `@alice ?` becomes `@alice?`. A Slack copy or a URL pasted over a selection converts on paste. It writes the model in bursts, before any click or command key.
- Not yet: Slack buttons in log cards and interview fields; inline spans don't cross lines, no setext headings or reference links, TextKit 1 limits Writing Tools to its panel, never checked in light mode.

**Sync** (`CaptainsLogKit/Sync/`)
- GitHub via `gh`: my PRs (50 per state per repo), open review requests made to me (`user-review-requested:@me`; team requests left out), the open and merged PRs (50 each) of people with `syncsPullRequests`, and PRs I reviewed on any request (`reviewed-by:@me`, updated in the last 30 days, 50 per repo), with my latest review's date (`myReviewedAt`). Any other PR still open locally is rechecked by number. A PR is a review request (`isReviewRequest`) once requested, for good, even if a teammate fetch found it first; one only a teammate or reviewed fetch found is `isTeammateOnly`, so a PR I reviewed on a team request shows with teammates' PRs. Merged and closed fetches leave out `reviewDecision`, which times out. Calendar via `gws`: timed events from the primary calendar, incremental with a full fetch each Monday; all-day events from the allowlist; attendees linked for events under 15 people. Merged PRs leave the dashboard and age out of the PR list by merge date.
- Each source runs its own `Task.sleep` loop in the app. Failures record per source in `SyncHistory` (`captains-log status`); GitHub saves what worked and report the rest.
- SwiftData's persistent history can't be switched off and nothing reads it, so the app's hourly loop deletes transactions older than 14 days (`HistoryPruner`). Most of it is typing autosave on meetings and interviews. Only the app prunes; the CLI never does.
- Not yet: Slack, Notion, Linear and Drive transcripts (Slack is deferred). Only the latest of my reviews of a PR is dated; the app doesn't show it.

**Backups** (`CaptainsLogKit/Backup/`, `captains-log/BackupCommand.swift`, `Views/BackupSettingsSection.swift`)
- `Backup.create`, run by the app and by `captains-log backup` (`just backup`): a snapshot through SQLite's backup API (`SQLiteFile`, source opened read-only) plus `sync-history.json`, `integrity_check`, `tar -cJ`, encrypted with `age` to `recipient.txt` in `~/Google Drive/My Drive/CaptainsLog backups/`. Keeps the newest Settings → Backups' "Keep the newest" (default 30, 7 to 90).
- The app checks hourly and backs up when the last success is older than the interval set in Settings → Backups (1 hour to 1 day, default a day; `Backup.isDue`). Outcomes record as the `backup` source in `SyncHistory`; a failure stays in the menu bar until a backup succeeds. Scratch stores skip the schedule. `captains-log backup` records too.
- Settings → Backups shows the current state (`Backup.status()`): an offer to set up, then three steps (Google Drive for desktop, `age`, a passphrase), each ticking off as it's found; rechecked when the app comes to the front. Once set up: the newest backup's age and size, the last error, frequency, how many to keep, Back Up Now and Show in Finder. Creating the key from there runs the first backup.
- A scratch store's Drive is a stand-in folder, `<store>/Google Drive`, so a sandbox never touches the real one. `CAPTAINSLOG_DRIVE_DIR` overrides it.
- `Backup.createKey`, from Settings and from `captains-log backup-setup` (`just backup-setup`, terminal only, reads the passphrase without echo), creates `identity.age` (the private key, passphrase-encrypted) and `recipient.txt`, both read-only; it refuses if `identity.age` exists, and passphrases under 8 characters. `age -p` only reads a terminal, so it runs under `script(1)`, the key goes in through a fifo, and the result is decrypted back before it's kept.
- `captains-log restore` (`just restore`), in a terminal only (it needs the passphrase): waits for the app to quit (real store only), lists backups newest first, decrypts with `age -i identity.age` so the private key never touches disk (age runs on the terminal through `runInteractiveProcess`, since `Process` puts children in a background process group that can't read it), unpacks and runs `integrity_check` in a temp dir, confirms, then moves the data folder aside to `CaptainsLog-before-restore-<time>` and moves the backup in. Nothing changes until the last step. The aside folders are never deleted automatically.
- Not yet: restore tried against the real store and Drive.

**Summaries and LLM**: nothing yet. Planned: transcript to meeting summary, a weekly summary that leaves out private entries, natural-language search. The `weekly-review` skill does the weekly write-up through Claude Code instead.

**Schema not yet used**
- `EntrySource.slack` and `.linear` have no importer. `Incident` and `Document` were removed on 2026-10-25 (nothing created them); a `LogEntry` tagged `incident` covers incidents until PR links are wanted.
- Fields no UI sets: `LogEntry.people`, `externalID`; `Meeting.project`, `tags`, `externalURL`; `CalendarEvent.meetingURL`, `participantCount`, `confirmedCount`; `PullRequest.project`, `tags`; `Feedback` beyond person, date and content; `Todo.pullRequest`.

## Tests

Swift Testing in the app host (`just test`). Covered: the Dashboard agenda's day, smart lists, When, ordering and grouping of todos; projects; person merge; roster import and export; markdown and Slack conversion; the native editor's line scanner and incremental restyle; `@`/`#` completion; calendar deletes; scorecard todos; search matching and coverage; sync history; history pruning; scratch-store isolation. Not covered: GitHub and calendar sync themselves, `Feed`, the CLI. The UI test target is template stubs.
