# CLI

`captains-log` is how Claude Code reaches the store (through the skills in `skills/`), so every record and field the app shows should be readable from it, and the things an agent produces (summaries, notes, todos) writable.

Each subcommand is a file in `Sources/captains-log/`, registered in `CaptainsLog.swift`. List DTOs are in `JSONOutput.swift`, `show`'s full records in `DetailOutput.swift`. `captains-log <command> --help` has every option.

## Conventions

- JSON to stdout (`--pretty` for humans), errors to stderr as `ValidationError` with a non-zero exit. Invalid input is an error, never ignored.
- Every record carries its `id`. Lists leave out long-form text (meeting notes, transcripts, PR bodies, interview sections) so a week fits in an agent's context; `show` prints everything. Text that is the record itself (log content, todo and project notes) stays in lists. Every DTO of a model with `isPrivate` includes it.
- Private records keep their text to `show`: `log list` and `todos list` drop their content and notes, `feed` their snippet, and `search` its snippet unless the title matched. The app's Feed and Search still show it.
- Dates go through `CLIDate` (`Dates.swift`): `YYYY-MM-DD` in local time, `--to` inclusive, impossible dates rejected. Lists default to the last week.
- Long-text options take `-` to read stdin (`TextInput`). Where the app clears a field by emptying it, an empty value clears.
- Permanent changes need a flag, since the CLI can't ask: `--permanently` for deletes, `--yes` for merging people and importing a roster, `--complete-todos` where the app confirms. Todos have a Trash; nothing else does.
- Only `backup-setup` and `restore` are interactive: they prompt on stderr and refuse without a terminal.
- Defaults match the app's creation paths: privacy (CLAUDE.md), a new todo's `TodoOrdering.topSortOrder`, a new project at the bottom of the column.

## Rules

- **Never point a write at the real store while developing.** Run `.build/debug/captains-log` with `CAPTAINSLOG_STORE_DIR` set to a scratch directory seeded by `CAPTAINSLOG_STORE_DIR=/tmp/x bash scripts/seed-data.sh`.
- **Upserts fetch first** (CLAUDE.md). Projects go through `ProjectNaming`, and commands never create one implicitly.
- **Shared rules go in CaptainsLogKit,** where the app can use them and tests can reach them (`SmartList`, `TodoWhen`, `ProjectCompletion`, `Person.absorb`, `Roster`, `Feed`, `Searcher`, `SyncHistory`). Keep command files thin.
- **One store, WAL.** The app sees CLI writes through `@Query`; views reading relationship arrays don't update.
- **Smoke-test by hand** against the scratch store, error paths included. `just ui-build` when CaptainsLogKit changed.
- **When a command changes,** update `skills/captains-log/SKILL.md` (and `skills/weekly-review/` if it reads the command). The installed CLI comes from the latest release, so until then try a new command with `.build/debug/captains-log`, or `just install-app` to install the checkout over Homebrew's.
