# Captain's Log

Personal work-tracking app: macOS SwiftUI app + `captains-log` CLI sharing code via the `CaptainsLogKit` Swift package. Replaces the manual weekly log compilation done across Slack, GitHub, Notion, Calendar, Linear.

Single user, unsandboxed, local-only. No CloudKit. No iOS. Targets the latest macOS and SwiftData; no backwards-compatibility code or version-availability checks.

## Build

Uses `just` (see `justfile` for all recipes). Key commands:
- `just ui-build` — build the Debug app (the copy `just ui` drives)
- `swift build` — build the CLI into `.build/debug/captains-log`
- `just test` — run the unit tests (see Testing)
- Users install the release with Homebrew (`brew install --cask nindalf/tap/captains-log`), the recommended way. `just release <version>` builds, notarizes and publishes it, and the cask from `homebrew/captains-log.rb` to `nindalf/homebrew-tap`; `just verify-release <version>` checks a release against its tag. `just install-app` installs the working tree over a Homebrew install (`docs/building-from-source.md`).
- `just backup` / `just restore` — `captains-log backup` / `restore`: an encrypted snapshot of the real store into Google Drive, and back (`Sources/CaptainsLogKit/Backup/Backup.swift`, which the app also runs daily). Run backup before anything that could touch the store (schema changes especially). Restore is interactive and for the user only. Try them with `CAPTAINSLOG_STORE_DIR` and `CAPTAINSLOG_DRIVE_DIR` (or `CAPTAINSLOG_BACKUP_DIR`) pointing at temp dirs, never the real Drive folder; `BackupTests` covers a round trip. Sandboxes get a stand-in Drive at `<store>/Google Drive`, missing until you create it.
- Seed the sandbox with `just ui-seed` / `just ui-private-seed`: four weeks of demo data (two past, this, next) from `seed-demo` (`Sources/captains-log/SeedDemo*.swift`), placed relative to now. It refuses the real store and any non-empty store. `just demo` reseeds `just ui`'s sandbox, launches it and starts Claude Code on its store (for recording the weekly review); it's the user's, don't run it.

## Seeing the UI

Drive a sandboxed copy of the app, never the real one. The user often clicks around in `just ui`'s sandbox, so use your own copy: `just ui-build`, `just ui-private-seed`, `just ui-private launch`, then `just ui-private shot <name>` (PNG in `.build/ui/shots/`, 1x so pixels = click points), `tree`, `click X Y [--cmd] [--shift]` / `dclick` / `rclick`, `drag X1 Y1 X2 Y2`, `key cmd+n`, `type <text>`, `quit`. Sandboxes set `CAPTAINSLOG_STORE_DIR` and skip sync (`Store.isScratch`).

- Screenshot, then click by coordinates; `press <label>` can match the wrong element.
- If the store or screen changes in ways you didn't cause, the user is probably clicking in your window too. Ask; don't chase it as a bug.
- Synthetic typing doesn't reach a new todo draft's title field (it does reach other fields).
- The driver can segfault walking the accessibility tree right after launch; retry.
- It can't scroll or hover. To scroll, post a throwaway `CGEvent(scrollWheelEvent2Source:...)` at window coordinates. Window shots miss tooltips (they're separate windows).
- Sandboxes share the real app's settings. To try a setting, pass it as a launch argument, which is never saved: `open -n <app> --env CAPTAINSLOG_STORE_DIR=... --args -hiddenSidebarTabs '(todos, log)'`.
- The menu bar, Quick Entry and the calendar event popover need the real screen: hand those to the user.

## Testing

Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) and run through Xcode, not SPM.

- `just test` — fast unit tests (`captainslogTests`). `just test-only <Name>` — a subset. Requires `xcbeautify` (`brew install xcbeautify`).
- **Not `swift test`.** SwiftData `insert`/`save` crashes (SIGTRAP) under SPM's test runner; SwiftData-backed tests must run in the app host via `xcodebuild`.
- Add a test by dropping a `.swift` file into `captainslog/captainslogTests/` — synchronized groups pick it up, no Xcode wiring.
- Imports: `import CaptainsLogKit` for models/logic; `@testable import Captain_s_Log` for app code (the module is `Captain_s_Log` — the product name `Captain's Log` with spaces to underscores, not `captainslog`).
- Logic over models usually needs no container: build models without inserting them (relationships can be set too), as `SmartListTests` does.
- SwiftData tests, three rules learned the hard way (see `PersonMergeTests.swift`):
  - **One container per process.** Creating a second `ModelContainer` for these models crashes (SIGTRAP). Use one shared static in-memory container per suite; don't make a fresh one per test.
  - **`@Suite(.serialized) @MainActor`.** Swift Testing runs tests in parallel; concurrent SwiftData access crashes.
  - **Don't batch-delete to reset.** `context.delete(model:)` violates the mandatory Person↔Meeting nullify inverse. Don't reset the store — each test uses its own objects and scopes any lookups by id.
  ```swift
  private static let container: ModelContainer = {
      let config = ModelConfiguration(isStoredInMemoryOnly: true)
      return try! ModelContainer(for: Schema(CaptainsLogSchemaV1.models), configurations: [config])
  }()
  ```
- Test sync correctness, search, summary, and merge logic — not tests for their own sake.

## Backlog

Bugs and planned work are GitHub issues on this repo, which is public: `gh issue list`, `gh issue view <n>`. Labels: `before-sharing` (needed before colleagues use it), `bug`, `ui`, `simplify`, `enhancement`. Close an issue when its change lands (`Fixes #n` in the commit), and file a new one for a gap you find rather than writing it into a doc. Keep issues free of anything about colleagues, the employer, or the user's own data.

## Read on demand

Don't read docs up front. Pull in what the task needs:
- **`docs/overview.md`** — how the app fits together, and the rules by area that aren't obvious from the code. Read before feature work or reviews.
- **`docs/todos.md`** — before any Todos or Projects work: list rules and gotchas.
- **`docs/cli.md`** — before CLI work: conventions and rules.

Docs hold decisions and traps, not descriptions of the code or todos. When a change adds a rule or a trap, add it to the doc.

## Correctness footguns

NEVER EVER MESS WITH THE LOCAL DATA. IT IS INVALUABLE.

The few rules where one mistake silently breaks things:

**SwiftData upsert: fetch first, never rely on `#Unique` alone.** Constructing a fresh `@Model` and inserting it upserts on the unique key but wipes relationships in the process. Pattern: fetch by predicate → mutate fields in place → only `insert` if not found. Wrap in a per-model helper.

**`@Model` is not `Sendable`.** Don't pass `LogEntry` / `Meeting` / etc. across actor boundaries. Pass IDs and refetch on the destination actor.

**`Process` shell-outs use the `runProcess` helper.** Never `waitUntilExit()` before draining stdout/stderr — deadlocks when child output exceeds the kernel pipe buffer. Arguments as `[String]`, no shell quoting.

**No `import SwiftUI` or `import AppKit` in `CaptainsLogKit` or the CLI target.** UI frameworks are app-target-only.

**Don't display relationship arrays** (`project.todos`, `person.feedback`) in views. Inserting from the other side doesn't notify observers, so the view goes stale. Filter a `@Query` instead.

**`onKeyPress` closures go stale.** SwiftUI keeps calling the closure from an earlier render, so a plain input property it reads can be out of date. Anything a key handler reads must be `@State`, `@Query` or a reference type. The Delete key arrives as U+007F, which `onKeyPress(.delete)` doesn't match; match `press.characters`.

**Schema changes: test on a copy first.** While the store has one user, a model change is an in-place edit of `CaptainsLogSchemaV1`, which SwiftData migrates when it opens the store. For each change:
1. `just backup`.
2. Snapshot the real store into `.build/migration-test/` with `sqlite3 .backup` (read-only on the source).
3. Open the copy with the new build (`CAPTAINSLOG_STORE_DIR`, CLI first, then the app). Compare row counts and every relationship before and after: the join tables get renumbered, so compare joined values, not table names.
4. Release, then `brew upgrade --cask captains-log`, which replaces the app and the CLI together.

Once a colleague has a store, every change needs a V2 and a migration stage (issue #5).

## Default patterns

- **Concurrency**: `@MainActor` for UI; `@ModelActor` for SwiftData writes during sync; `Task.sleep` loops for periodic sync (not `Timer`); plain `Task { }` not `Task.detached`; `async let` / `TaskGroup` for parallel work; `try Task.checkCancellation()` periodically in long loops.
- **SwiftData**: `@Query` in views; `relationshipKeyPathsForPrefetching` on list-view fetches; `fetchCount` for counts; batch many writes then one `save()`. Push filters into `#Predicate`; fall back to Swift filtering only when the macro can't compile.
- **SwiftUI**: `@Observable` for reference-type state (not `ObservableObject` / `@Published` / `@StateObject`); `@Environment` for long-lived DI; `.task { }` modifier for view-scoped async work; `ForEach` over `Identifiable`. Don't mutate state inside `body`.
- **Errors**: `throws` over `Result` (use `Result` only for storing deferred outcomes); custom `Error` enum per subsystem; `LocalizedError` for user-facing; treat `CancellationError` as a sentinel.
- **CLI**: subcommand structs conforming to `AsyncParsableCommand`; JSON to stdout by default, `--pretty` for humans; diagnostics to stderr; non-zero exit on errors; non-interactive.
- **Models**: `final` on every `@Model class`; native enums (not raw strings); explicit `@Relationship(deleteRule:inverse:)` on every relationship; `@Attribute(.indexed)` on hot query fields.
- **Privacy**: `isPrivate` is false by default, true for interviews. A todo filed from an interview or meeting copies its `isPrivate` when created (`LinkedTodoList`), except the automatic scorecard todo (`ScorecardTodo`), which is never private. The CLI leaves private records' text to `show` (docs/cli.md).
- **Logging**: `os.Logger` with subsystem `"com.nindalf.captainslog"` and a category per source (`"sync.github"`, `"search"`, etc.). Not `print`.

## Don'ts

- No CloudKit. No iOS target. No App Sandbox.
- No new `@Model` classes without discussion — use `LogEntry` with tags for one-off cases (weekly summaries, reflections, status updates).
- No new dependencies without checking. Current deps: `swift-argument-parser` (CLI), `swift-markdown` (Kit, pulls in `swift-cmark`). Depend on tagged releases, not branches.
- No MCP / Slack ingestion code yet — deferred until explicit go-ahead.
- No backwards-compat shims for older macOS or SwiftData.
- No tests just to add tests — write them for sync correctness, search, summary generation.
- No emojis in code or comments. No tutorials. No multi-paragraph docstrings.
- No pre-emptive error UI for sync failures — surface in a status pill on the menu bar.
- No destructive git operations (force push, hard reset, branch deletion) without explicit instruction.
- Other work happens in the same checkout. Stage explicit paths, and check `git diff --cached --stat` before committing: anything already staged (a `git rm`, say) goes into the commit too.
