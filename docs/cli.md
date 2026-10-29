# CLI

`captains-log` is how Claude Code reaches the store (through the skills in `skills/`), so every record and field the app shows should be readable from it, and the things an agent produces (summaries, notes, todos) writable. What it lacks against the app is in `docs/overview.md`.

Each subcommand is a file in `Sources/captains-log/`, registered in `CaptainsLog.swift`. List DTOs are in `JSONOutput.swift`, `show`'s full records in `DetailOutput.swift`.

## Commands

| Command | Does |
|---|---|
| `show <id>` | Any record in full, whatever its type, with refs to linked records. `type` says which |
| `status` | When GitHub and calendar last synced, and the app's last backup (`SyncHistory`) |
| `feed` | The Log tab's merged feed for a date range (`--type`), with snippets (`Feed`) |
| `search <query>` | Every word, across people, projects, todos, log, meetings, interviews, PRs and feedback, with `matchedField` and a snippet (`Searcher`); people and open projects have no `date` |
| `log` | `list`, `add`, `edit`, `delete --permanently`. `add` and an `edit` of the title or content link the people the text tags, as in todos; `people` lists their names, and `show <person>` lists the entries |
| `meetings` | `list`, `add --event <id>` (`CalendarEvent.createMeeting`), `edit` |
| `events` | `list` (overlapping the range; `--hidden`), `hide`, `unhide`, `delete --permanently` (`deleteWithEmptyStubs`) |
| `interviews` | `list`, `add`, `edit` (every section) |
| `prs` | `list` (one of `--mine`, `--reviews`, `--teammates`, with `--state`), `edit` (notes) |
| `todos` | `list` (`--list`, `--project`, `--overdue`), `add`, `edit`, `complete`, `reopen`, `trash`, `restore`, `delete --permanently`, `empty-trash --permanently` |
| `projects` | `list`, `add`, `edit`, `complete`, `reopen`, `delete --permanently`; by name or UUID |
| `people` | `list` (meaningful contacts; `--all`, `--search`), `edit` (`--sync-prs` / `--no-sync-prs`), `merge --yes`, `import <file>` (a preview; `--yes` applies), `export` (`--all`, `--teammates`, `--person`), `feedback list/add/edit/delete` (`Roster`) |
| `sync` | GitHub and calendar, with the app's settings from its `com.nindalf.captainslog` defaults domain |
| `seed-demo` | Hidden. Demo data into an empty scratch store, for `scripts/seed-data.sh` |

`captains-log <command> --help` has every option.

## Conventions

- JSON to stdout (`--pretty` for humans), errors to stderr as `ValidationError` with a non-zero exit. Invalid input is an error, never ignored.
- Every record carries its `id`. Lists leave out long-form text (meeting notes, transcripts, PR bodies, interview sections) so a week fits in an agent's context; `show` prints everything. Text that is the record itself (log content, todo and project notes) stays in lists. Every DTO of a model with `isPrivate` includes it.
- Dates go through `CLIDate` (`Dates.swift`): `YYYY-MM-DD` in local time, `--to` inclusive, impossible dates rejected. Lists default to the last week.
- Long-text options take `-` to read stdin (`TextInput`). Where the app clears a field by emptying it, an empty value clears.
- Permanent changes need a flag, since the CLI can't ask: `--permanently` for deletes, `--yes` for merging people and importing a roster, `--complete-todos` where the app confirms. Todos have a Trash; nothing else does.
- Defaults match the app's creation paths: privacy (CLAUDE.md), a new todo's `TodoOrdering.topSortOrder`, a new project at the bottom of the column.

## Rules

- **Never point a write at the real store while developing.** Run `.build/debug/captains-log` with `CAPTAINSLOG_STORE_DIR` set to a scratch directory seeded by `CAPTAINSLOG_STORE_DIR=/tmp/x bash scripts/seed-data.sh`.
- **Upserts fetch first** (CLAUDE.md). Projects go through `ProjectNaming`, and commands never create one implicitly.
- **Shared rules go in CaptainsLogKit,** where the app can use them and tests can reach them (`SmartList`, `TodoWhen`, `ProjectCompletion`, `Person.absorb`, `Roster`, `Feed`, `Searcher`, `SyncHistory`). Keep command files thin.
- **One store, WAL.** The app sees CLI writes through `@Query`; views reading relationship arrays don't update.
- **Smoke-test by hand** against the scratch store, error paths included. `just ui-build` when CaptainsLogKit changed.
- **When a command changes,** update the table above, `skills/captains-log/SKILL.md` (and `skills/weekly-review/` if it reads the command), then `just install-cli` so the installed binary matches. `just install-skills` links the skills into `~/.claude/skills`.
