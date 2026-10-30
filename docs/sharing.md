# Sharing with colleagues

The work needed before colleagues can build, review and use Captain's Log. Tackle top to bottom; delete an item once it's done.

## The pitch

Written up in the README: the day-to-day value in "What you get", the promises in "Reviewing the code", the rest in "How it's built". Each one is a promise the code has to keep.

1. **One look, and you know what to do next.** Slack is unavoidable; GitHub, Calendar and a todo app shouldn't be. The dashboard routes you to the source app; it doesn't replace it.
2. **Fetch and store, nothing more.** No AI, no spend, never writes to an external system. It only reads from `gh` and `gws`.
3. **The data stays on company hardware.** That's why it's a local SQLite store and not an iOS app with iCloud. Backups go to the company Google Drive, encrypted so no other employee can read them.
4. **A database underneath, Claude on top.** Retrieval is a SQLite query through the `captains-log` CLI: fast, deterministic, free, and no slower as the store grows. Claude summarises and drafts over what the query returns.
5. **Make it yours.** It's tailored to one person (the interview flow, the dashboard). Fork it and customise; send back PRs for what others would want. Stay close to the architecture to keep pulling in improvements, or diverge, which is fine too.

## Blockers: the pitch isn't true without these

- [ ] **Install experience.**
  - The README's prerequisites and `gws` steps are written but untested on a fresh Mac. Check `gws auth setup` and `gws auth login --readonly -s calendar` end to end.
  - Find `gh` and `gws` on `PATH` instead of hardcoding them (`GitHubSync.swift:7`, `CalendarSync.swift:7`).
- [ ] **Try a restore for real.** `just restore` is built and tested against temp folders. Run it once against the real Drive folder (the newest backup), check the app, then delete the `-before-restore-` folder or move it back.
- [ ] **Settle the schema before anyone else has data.** Once colleagues have data, every model change needs a `VersionedSchema` migration. `Incident` and `Document` are gone; decide about the fields no UI sets (listed in `docs/overview.md`). Put a `SchemaMigrationPlan` in place so the first real change isn't improvised. Run `just backup` first.
- [ ] **Security review guide.** Done in the README's "Reviewing the code" and `docs/security.md`, except optional `gh` hardening: a read-only fine-grained token via `GH_TOKEN`. Check that `gh pr list` still works with one, then document it.

## Should do before sharing: the first hour shouldn't hurt

- [ ] **Restore without a clone.** Homebrew, the recommended install, doesn't include `scripts/restore.sh`, so restoring a backup needs a clone and `just`. Bundle it like `backup.sh`, behind `captains-log restore` or a Settings button.
- [ ] **Setup checklist on the empty dashboard:** install `gh`, authorise `gws`, add repos, import a roster (People > Roster). Each step ticks off as its source starts working.
- [ ] **Freshness on the dashboard.** Show last sync time and errors where you look, not only in the menu bar.
- [ ] **Fix the bugs a newcomer hits early** (from `docs/overview.md`):
  - The Log Delete key does nothing.
  - The interview filter chips use `x`/`?` but the copied key says `-`/`!`.
  - The interview stub drops `problemName`.
- [ ] **Fork guidance in `CLAUDE.md`.** Shared core: CaptainsLogKit, models, sync, CLI. Meant to be personal: views, the interview flow, `InterviewHeuristic`, the dashboard. For new kinds of data, prefer `LogEntry` with tags; a model change is the point where a fork diverges.

## Soon after: makes "one look" stronger

- [ ] **CI status and unresolved comments on PRs.** Add `statusCheckRollup` to `prFields` in `GitHubSync`; these are the main remaining reasons to open GitHub.
