# Todos

The Todos tab copies Things 3's macOS UX: collapsed rows, an expanded card with no form, metadata as pills, popovers from icons, auto-save. Left out on purpose: This Evening, tags on todos. Read this before touching todo or project code.

## Model rules

- `dueDate` is the "when" date, stored as start of day. There is no separate deadline.
- `schedule`: only `.someday` matters; `.inbox` and `.anytime` both mean "not Someday".
- `sortOrder` is one order across **all** open todos; each list shows a slice of it.
- `isTrashed` and `isCompleted` are computed from `trashedDate` and `completedDate`, so predicates test the dates.
- A todo filed from an interview or meeting copies its `isPrivate` at creation. The automatic "Submit scorecard" todo is the exception: it's never private.

## Lists

`SmartList.of(todo)` gives a todo's one home list, checked in order: Trash, Logbook, Today (dated today or earlier), Upcoming (later), Someday, Anytime (undated, in a project), Inbox (everything else). `contains(todo)` is what a list shows: the same, except Anytime also shows every dated todo, and People (never a home list) shows every open todo that tags someone.

`.people` is titled By person and `.logbook` Completed, to keep them apart from the People and Log tabs. The CLI's `--list` takes the case names.

Anytime and People take no new todos: nothing would file one in Anytime, and in People a tag decides who a todo is for.

## Tagging people

`@` tags in a todo's title or notes link it to people (`Mentions.swift`). A tag matches a Slack handle, GitHub handle or full name, ignoring case; the longest match wins, and a handle beats a name of the same length.

- The text decides: relinking sets `people` to exactly the tagged set, so deleting a tag unlinks.
- A card relinks as it closes (`TodoCardView.onDisappear`), not per keystroke, so a todo doesn't drop out of a meeting's list mid-edit.
- A meeting's Todos section (`LinkedTodoList`) adds open todos tagging any attendee. Checking one off there stamps `completedInMeeting`, so it stays in that meeting's list.

## Gotchas

- **Don't relate an unsaved draft to a saved model** until you mean to keep it: that inserts the draft. That's why Quick Entry holds its project in `projectID` until Save, and `commitDraft` sets the project only on commit. Never relink people on an uninserted draft.
- **Project names are `#Unique`,** and a clash silently upserts over the other project. Always go through `ProjectNaming`.
- **`sortOrder` is global.** Use `TodoOrdering.makeUnique` before a reorder and `topSortOrder` for new todos.
- **Drag heights are load-bearing.** Reordering is a hand-rolled `DragGesture` that computes the live order from fixed heights: rows must stay exactly `rowHeight` (44) and headings `headingHeight` (48), or drops land in the wrong place.
- **Dragging in Upcoming renumbers by date,** so dated todos in Anytime end up in date order too.
- **Quick Entry's panel must stay borderless and size itself** (`fit(height:)`). A titled panel sized by Auto Layout grew on every pass through the title bar's insets until AppKit threw.
- **Use `Navigator`, not `@SceneStorage`, for the selected list.** `@SceneStorage` reset when focus moved into the list. The column uses plain buttons because `List(selection:)` didn't highlight its stored selection.
- **No SwiftData undo.** Saving after undoing a delete crashed (`swift_dynamicCast`). The Trash exists instead.
