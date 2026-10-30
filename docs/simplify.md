# Simplification

What to remove or merge so the app stays small and consistent. From a review on 2026-10-25, after `Incident` and `Document` were removed (2314029). Work top to bottom; delete an item once it lands, and move lasting rules into `overview.md`.

UI layout work is in `docs/ui-rework.md`, not here.

## Schema changes: how

While the store has one user, a model change is an in-place edit of `CaptainsLogSchemaV1`, which SwiftData migrates when it opens the store (as `Remove tags from todos` and `2314029` did). For each batch:
1. `just backup`.
2. Snapshot the real store into `.build/migration-test/` with `sqlite3 .backup` (read-only on the source).
3. Open the copy with the new build (`CAPTAINSLOG_STORE_DIR`, CLI first, then the app). Compare row counts and every relationship before and after: the join tables get renumbered, so compare joined values, not table names.
4. The user switches over by releasing it and running `brew upgrade --cask captains-log`, which replaces the app and the CLI together, so they change schema at the same time.

Once a colleague has a store, this stops working: every change then needs a V2 and a migration stage (see `docs/sharing.md`).

## 1. Unused fields

Nothing sets these, in the app or the CLI (checked outside the demo seed and previews); the CLI's `show` only prints them. Remove in one batch, with their CLI output.

| Model | Fields |
|---|---|
| LogEntry | `externalID`, `externalURL` |
| Meeting | `project`, `tags`, `externalURL` |
| PullRequest | `project`, `tags` |
| CalendarEvent | `participantCount`, `confirmedCount` (calendar sync sets them; nothing reads them) |

Undecided: `CalendarEvent.meetingURL` is synced but shown nowhere. Either show a Join button on events or remove it.

## 2. Duplicates

- The Calendar tab's List view (`MeetingViewMode` in `MeetingListView`): bare, not the default. Remove it and the `meetingViewMode` setting.

## 3. Smaller consistency fixes

- `TodoSchedule` has three cases but only `.someday` changes anything (`.inbox` and `.anytime` mean the same). Make it a Bool.
- Settings that are only knobs: sync intervals and weeks to fetch. Fix the defaults and drop the controls.
- `EntrySource` has `.slack` and `.linear` with no importer (Slack is deferred). Leave it until ingestion is decided; check the real store for rows using them before removing either case.
