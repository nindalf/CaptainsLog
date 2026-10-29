# Todos

How the Todos feature works, where the code lives, the traps, and what's left. It copies Things 3's macOS UX: collapsed rows, an expanded card with no form, metadata as pills, popovers from icons, auto-save. Read this before touching todo or project code.

## Model

`Todo` (`Sources/CaptainsLogKit/Models/Todo.swift`):
- `dueDate` is the "when" date, stored as start of day. There is no separate deadline.
- `scheduleRawValue` / `schedule` (`TodoSchedule`): only `.someday` matters. `.inbox` and `.anytime` both mean "not Someday"; the model default is `.anytime`.
- `sortOrder` is one order across **all** open todos. Each list shows a slice of it.
- `trashedDate` puts a todo in the Trash; `completedDate` in the Logbook. `isTrashed` and `isCompleted` are computed from them, so predicates test the dates.
- `notes` is markdown. `isPrivate` is false by default; a todo filed from an interview or meeting copies its privacy at creation. The card's controls sit at the bottom right: project, When, eye, trash (`TodoControls`).
- `people` is whoever the title and notes tag (below).

## Tagging people

`@` tags in a todo's title or notes link it to people (`linkMentionedPeople` on `MentionsPeople`, which log entries share, and `Mentions`, both in `Sources/CaptainsLogKit/Mentions.swift`). A tag matches a Slack handle, GitHub handle or full name, case-insensitively, since completion inserts the Slack handle and falls back to the name. The longest match wins; a handle beats a name of the same length; people sharing a name or handle are all linked. A tag that matches nobody stays plain text.

- The text decides: relinking sets `people` to exactly the tagged set, so deleting a tag unlinks.
- When: a card relinks as it closes (`TodoCardView.onDisappear`), not per keystroke, so a todo doesn't drop out of a meeting's list while its tag is being edited. Quick Entry relinks on Save, the CLI on `add` and on `edit` of the title or notes. A committed draft relinks when its card goes. Never relink an uninserted draft: relating it to a person inserts it.
- Shown: a person page's Open Todos, and a meeting's Todos section, which adds open todos tagging any attendee after the meeting's own (`LinkedTodoList`). Checking one off there stamps `completedInMeeting`, so it stays in that meeting's list, among the completed ones; reopening clears it. Those are sorted by the names of the attendees they tag, which show at the row's trailing edge, so a todo tagging Priya and Sarah sits between Priya's and Sarah's. Both read the todos `@Query` and filter in Swift, not `person.todos`.

`Project` (`Models/Project.swift`): `name` is `#Unique`. Also `notes`, `completedDate` (`isCompleted` is computed from it), `sortOrder` (order in the column), and `iconName` (an SF Symbol; nil means the default folder).

## Lists

`SmartList` (`Sources/CaptainsLogKit/SmartList.swift`):
- **`of(todo)`** gives the todo's one home list, checked in this order: Trash, Logbook, Today (dated today or earlier), Upcoming (dated later), Someday, Anytime (undated, in a project), Inbox (everything else).
- **`contains(todo)`** says what a list shows. It equals `of`, except that Anytime also shows every dated todo, and People, which is never a home list, shows every open todo that tags someone.

Two lists are titled differently from their cases, to keep them apart from the Log and People tabs: `.people` is By person and `.logbook` is Completed (Things' Logbook). The CLI's `--list` takes the case names. The rest of this doc uses the case names.

| List | Shows | Layout | Reorder | New todos |
|---|---|---|---|---|
| Inbox | no project, no date, not Someday | flat | yes | yes |
| Today | dated today or earlier | grouped by project | yes | yes, dated today |
| Upcoming | dated after today | by day for 6 days, then by month (`TodoUpcomingGroup`) | yes, and dragging under another heading changes the date | yes, dated tomorrow; Space takes the selected todo's date |
| Anytime | project or date, not Someday | grouped by project | yes | no: nothing would file it there |
| Someday | set to Someday | grouped by project | yes | yes |
| People (By person) | open todos that tag someone | one section per set of tagged people (`TodoPeopleGroup`) | within a section only | no: a tag decides who a todo is for |
| Logbook (Completed) | completed todos and completed projects | Today, Yesterday, then by month (`TodoLogbookGroup`) | no | no |
| Trash | trashed todos, most recent first | flat, with Empty Trash | no | no |
| A project | its open todos, then a Completed section | `ProjectHeader` above | yes | yes, in the project |

**Grouped lists:** loose todos come first, under no heading, then one heading per project in column order (`TodoProjectGroup`). Clicking a heading opens the project.

**People:** a todo appears once, under the set of people it tags, so `@priya @sarah` has a "Priya Patel, Sarah Lin" section, sorted between Priya's and Sarah's (names compared in order). People sharing a name share a section. Each name in a heading opens that person (`PersonLinks`, tinted to read as a plain heading). A meeting's Todos section uses the same order. Untagging is the only way to move a todo between sections: drags and Cmd+↑/↓ stop at the section's edges.

**Project names and stars:**
- Inbox, Upcoming and Trash show a todo's project as grey text under its title, and so do Logbook rows.
- Grouped lists and project views don't, since the heading already names the project.
- In a project and in Anytime, a yellow star marks todos due today.

**Where Today also appears:** the Dashboard embeds the same list view (`TodoListContent(scope: .smart(.today))`), and the menu bar counts Today.

## When

`TodoWhen` (`Sources/CaptainsLogKit/TodoWhen.swift`) is `.day(Date)`, `.someday` or `.unset`, and applying it sets the todo's fields. Choosing a day ends Someday. `.unset` clears both, so the todo lands in the Inbox, or in Anytime if it's in a project.

The `TodoWhenPopover` offers:
- Today and Tomorrow
- a month calendar: › steps forward, ‹ appears once you've stepped ahead, past days are disabled
- Someday
- Clear, once something is set

The current choice is highlighted. The popover opens from right-click → When… (acting on the whole selection), the card's calendar icon, and the date pill.

## Projects

- **Create:** the + in the column makes "New Project", "New Project 2" and so on, and focuses the name for renaming via `Navigator.renamingProjectID`.
- **Rename:** goes through `ProjectNaming`, which refuses clashes.
- **Complete:** from the header or the column's context menu. `ProjectCompletion` completes the project's open todos too, and asks first if there are any.
- **Completed projects** leave the column and appear in the Logbook, where right-click offers Reopen and Delete.
- **Delete:** asks first and lists what will be unlinked (`Project.deletionSummary`). Every relationship nullifies, so nothing else is deleted.
- **Icons:** the header's icon opens `ProjectIconPicker`, which offers the 24 symbols in `ProjectIcon.choices`.
- **Filing todos into a project:** right-click → Project; Cmd+N or Space inside a project; Space below a todo in a grouped list (it joins that group); or drag in a grouped list.

## Interaction

**Mouse:**
- A click selects a row. Clicking the selected row opens its card.
- Cmd-click toggles a row in the selection. Shift-click selects the range from the anchor.
- Right-click offers When…, Project ▸ and Move to Trash. In the Trash it offers Restore and Delete Permanently…. It acts on the whole selection if the clicked row is part of it.
- The checkbox completes the todo after a 0.5 s pause. On a completed todo it reopens it, asking first if it was completed before today, since completing again dates it today (`ReopenConfirmation`, `Todo.reopenNeedsConfirmation`). Cmd+K reopening asks the same way.

**Keyboard:** handlers live on `TodoListContent`'s scroll view. While a card or a new draft is open, arrows and Delete go to its text fields.

| Key | Action |
|---|---|
| ↑ / ↓ | move; collapses any multi-selection |
| Shift+↑ / ↓ | extend from the anchor (`selectedID`; `cursorID` is the moving end) |
| Cmd+↑ / ↓ | reorder, within a project group in grouped lists, within a day in Upcoming and within a section in People |
| Return | open the selected row; close an open card or a new draft |
| Escape | discard an empty draft, close a card, or clear the selection |
| Space | new draft below the selection |
| Cmd+N / + | new draft at the top |
| Delete | trash the selection; does nothing in the Trash |
| Cmd+K | complete the selection, or reopen it if all are complete |
| Cmd+A | select every row |

**Drag:** reorderable lists use a hand-rolled `DragGesture`, not system drag and drop.
- **Live order:** the list is a sequence of `TodoListItem`s (rows, project headings, and Upcoming's date headings). The live order is computed from fixed heights: `rowHeight` 44 and `headingHeight` 48.
- **Drop:** hands the list's existing `sortOrder` values back out in the new order.
- **Grouped lists:** a todo joins the project whose heading sits above where it's dropped. Above every heading means no project.
- **People:** `TodoPeopleGroup.dropRange` clamps the drop to the dragged todo's own section.
- **Upcoming:** `TodoUpcomingGroup.dueDate` picks the date. Under a day heading the todo takes that day. In a month group it keeps its own date if that still sorts there; otherwise it takes the date of the todo above, or the group's first day at the top. A drop above every heading lands in the first group. Only headings that already exist can take a drop, since days with no todos get no heading.

**Drafts:** a new todo is an uninserted `Todo` until it's committed with a non-empty title. `commitDraft` sets its project at that point.

## Quick entry

Control-Space opens a floating panel from any app, Things' Quick Entry: title, notes and a card's controls (project, When, eye; no trash), then Cancel and Save. The project waits in `projectID` until Save, since relating the draft would insert it. Return in the title or Cmd+Return saves; Escape or Cancel discards. Off by default; Settings › Quick Entry turns it on.

- `QuickEntryController` registers the hotkey while `AppSettings.quickEntryEnabled` is on (`GlobalHotKey`, Carbon's `RegisterEventHotKey`: no Accessibility permission) and owns the panel. Each open builds a fresh view, so it starts blank.
- `QuickEntryPanel` is a borderless `.nonactivatingPanel`: it takes typing without bringing the app or its main window forward, and closing hands focus back. The view draws the rounded card; the system draws the shadow from it. The panel sizes itself to the height the view reports (`fit(height:)`), top edge fixed. It floats on every Space until dismissed.
- The draft is an uninserted `Todo` with the project held apart in `projectID`, set only on Save (see Gotchas). `TodoProjectPopover(current:projects:onPick:)` is the variant for that.
- If Control-Space switches input sources (System Settings › Keyboard Shortcuts › Input Sources), macOS takes it first. Things uses Control-Space for its own Quick Entry too.

## Code map

| Where | What |
|---|---|
| `Sources/CaptainsLogKit/` | `SmartList`, `TodoWhen`, `TodoOrdering`, `ProjectNaming`, `ProjectCompletion`, `Enums.swift` (`TodoSchedule`) |
| `Views/TodoListView.swift` | The tab: column, `ProjectHeader`, list, toolbar + (Cmd+N) |
| `Views/Todo/SmartListColumn.swift` | Smart lists and open projects, counts, project create, complete and delete |
| `Views/Todo/TodoListContent.swift` | The list itself: rows, headings, selection, keyboard, drag, drafts, context menus, When popover hosting |
| `Views/Todo/TodoRowView.swift`, `CompletedTodoRowView.swift`, `TodoTitleBadges.swift` | Collapsed rows; the badges after the title mark notes and link to the todo's meeting or interview (`Navigator.openMeeting` / `openInterview`) or open its PR on GitHub (the `GitHubMark` asset, GitHub's Octicon) |
| `Views/Todo/TodoCardView.swift`, `TodoControls.swift`, `Views/CardControls.swift` | The expanded card and its controls (also in the Log and Quick Entry) |
| `Views/Todo/TodoWhenPopover.swift`, `TodoProjectPopover.swift` | Card popovers |
| `Views/Todo/ProjectHeader.swift`, `ProjectIcon.swift` | Project view header, icons and picker, `deletionSummary` |
| `Views/Todo/TodoProjectGroup.swift`, `TodoUpcomingGroup.swift`, `TodoLogbookGroup.swift`, `TodoPeopleGroup.swift` | Grouping for the grouped lists, Upcoming, the Logbook and People |
| `Views/Todo/LinkedTodoList.swift` | The Todos section below a meeting or interview's first section: a draft from Cmd+N or the + by the section title, rows, cards. A meeting's also lists open todos tagging an attendee, and todos checked off in it (`Todo.completedInMeeting`); a person page's (Open Todos, no adding) lists those tagging them. All rows sit in one form row as compact 28 pt `TodoRowView`s (the form's own row insets doubled their height); past five, the rest wait behind Show More. Always rendered where todos can be added, since adding a section mid-typing rebuilds the form and steals focus. `ScorecardTodo` (Kit) adds "Submit scorecard for <candidate>", dated today, on an interview's first text |
| `QuickEntry/` | `QuickEntryController` (hotkey, panel), `QuickEntryView`, `GlobalHotKey` |
| `Navigator.swift` | `todoSelection` (`TodoSelection`: a smart list or a project id) |
| `Sources/captains-log/Todos.swift` | CLI, below |
| `captainslogTests/` | `SmartListTests` (and `TodoWhenTests`), `MentionsTests`, `TodoPeopleGroupTests`, `TodoOrderingTests`, `TodoProjectGroupTests`, `TodoUpcomingGroupTests`, `TodoLogbookTests`, `ProjectTests` |

**CLI** (`captains-log todos`):
- `list [--list <smart list>] [--project <name>] [--completed] [--overdue]`
- `add <title> [--due-date YYYY-MM-DD | --someday] [--project <name>] [--notes <text>] [--private]`
- `edit <id>` with any of `--title`, `--notes` / `--clear-notes`, `--due-date` / `--someday` / `--clear-when` (via `TodoWhen`), `--project` / `--no-project`, `--private` / `--no-private`
- `complete <id>`, `reopen <id>`, `trash <id>`, `restore <id>`
- `delete <id> --permanently` (only from the Trash), `empty-trash --permanently`

`--project` must name an existing project, because the CLI never creates one. `TodoDTO` includes `schedule`, `list` (the home list), `project`, `people` (names of those tagged) and `trashedDate`.

**Seed data:** the hidden, scratch-only `seed-demo` command (`SeedDemoTodos.swift`) makes four projects, one completed, and about seven todos per list, dated relative to today. Next week's Wednesday and Friday are left empty for the weekly review to fill.

## Gotchas

- **Real store and schema changes.** Run `just backup` first. `Todo.trashedDate` and `Project.iconName` reach the real store the first time the real app runs a build that has them. `CaptainsLog-20261018-103006.store` is the backup taken just before `iconName` was added.
- **Don't display relationship arrays** (`project.todos`, `person.feedback`). Inserting from the other side doesn't notify observers, so the view goes stale. Filter a `@Query` instead.
- **Don't relate an unsaved draft to a saved model** until you mean to keep it: doing so inserts the draft.
- **Project names are `#Unique`,** and a clash silently upserts over the other project. Always go through `ProjectNaming`.
- **`sortOrder` is global.** Use `TodoOrdering.makeUnique` before a reorder and `topSortOrder` for new todos.
- **No SwiftData undo.** Saving after undoing a delete crashed (`swift_dynamicCast`). The Trash exists instead.
- **Key handlers read stale inputs.** SwiftUI keeps calling `onKeyPress` closures from an earlier render, so a plain `let`/`var` input looks stale after a change. That's why `scope` is `@State`, synced from `requestedScope`. Anything else a key handler reads must be `@State`, `@Query` or a reference type.
- **The Delete key sends U+007F,** which matches neither `onKeyPress(.delete)` nor `.deleteForward`; `.deleteForward` matches only Fn-Delete. Match on `press.characters`. `LogListContent` still uses `.onKeyPress(.delete)`, so Delete is dead in the Log list.
- **Drag heights are load-bearing.** Rows and headings (project and date) must keep exactly `rowHeight` and `headingHeight`, or drops land in the wrong place.
- **Dragging in Upcoming renumbers by date.** A drop hands the Upcoming todos' `sortOrder` values back out in date order, so dated todos in Anytime end up in date order too.
- **Quick entry's panel must stay borderless and size itself.** A titled panel with a hidden title bar, sized by Auto Layout from its hosting view, grew a little on every pass through the title bar's insets until AppKit threw ("more Update Constraints in Window passes than there are views").
- **Use `Navigator`, not `@SceneStorage`, for the selected list.** `@SceneStorage` reset when focus moved into the list. The column uses plain buttons because `List(selection:)` didn't highlight its stored selection.

## What's left

**Left out of Things on purpose:** This Evening, tags on todos.

**Decisions taken that the user hasn't pushed back on:**
- The When popover has Clear.
- + is disabled in Anytime.
- Someday todos in a project stay out of Anytime.

**Known issues:**
- Delete doesn't work in the Log list (see Gotchas).
- `ProjectHeader` clips notes longer than one line.
- Does Cmd+N then typing work for real? The UI driver's synthetic typing never reaches a new draft's title field in the Todos tab, though it does reach other fields, and it does reach the draft in a meeting or interview's `LinkedTodoList`. It's probably a driver limitation, but unconfirmed.

**Backlog, roughly in order:**
1. Dragging a todo onto a smart list or project in the column. This needs a floating copy of the row above the scroll view, shared coordinates with the column, and hover highlighting. Within grouped lists, dragging between project groups already works.
2. Scheduling shortcuts acting on the selection: Cmd+T Today, Cmd+O Someday, Cmd+Shift+M move to project.
3. A progress pie on project rows.
4. Repeating todos (a recurrence rule on `Todo`, which is a schema change).
5. Needs discussion first (new `@Model`s or model changes): checklists inside a todo, project headings and Areas, deadlines separate from the When date.

## Next up, beyond the Todos tab

From a review on 2026-10-23. Tackle top to bottom; delete an item once it's done.

1. **Hide tabs in Settings**, so nobody forks just to drop Interviews. Also listed in `docs/sharing.md`.
2. **Linear integration.** Colleagues, the EMs especially, won't adopt the app without it. Before writing code:
   - Find out what the EMs' current workaround pulls (assigned issues, cycle progress, project status for weekly updates?).
   - No official Linear CLI exists, so this would be the first sync that isn't a shell-out: Linear's GraphQL API with a personal key in the Keychain. Read-only, so the app still never writes to an external system.
   - It most likely needs a new `LinearIssue` model, which needs discussion first. Don't copy issues into `Todo`: ticking one off locally wouldn't close it in Linear, and the two would drift apart. Something shaped like the PR tab: assigned to me plus my team's in-progress issues, counts on the dashboard and menu bar, clicking through to Linear. `EntrySource.linear` already exists, unused.
3. **Make the logo brighter** (`captainslog/captainslog/Assets.xcassets/AppIcon.appiconset/AppIcon.png`).
4. **A configurable interview scorecard.** The scorecard fields (`upsides`, `riskFactors`, `levelAssessment`, `recommendation`) are separate columns on `Interview`, so fully free-form sections would be a bigger model change. Middle path: theme buttons and section labels in Settings, sections that can be hidden, storage unchanged. Wait until a colleague asks.
5. **Google Groups as meeting attendees.** Out of scope: listing a group's members needs Directory API access most people don't have. A standup whose only attendee is the team's group won't show todos tagged with team members. A cheap fix later: the roster import maps a group email to member emails, and those members count as attendees when matching todos.
