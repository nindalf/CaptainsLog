# UI rework

What's left of a design review of every tab, from screenshots of the seeded private sandbox on 2026-10-24. Done so far: one date vocabulary, calendar-owned dates and `DayField`, detail pages as documents (`DetailPage`), and the Dashboard's agenda and boxed panes. Delete items as they land, and move anything that becomes a lasting rule into `overview.md` or `todos.md`.

Not reviewed: the menu bar, the Quick Entry panel and the calendar event popover (they need the real screen; hand those to the user).

To look again: `just ui-build`, `just ui-private-seed`, `just ui-private launch`, then `shot`. The user often clicks in `.build/ui-claude` too; for a clean look, copy the app and seed a store under another `.build/ui-claude*` directory and drive it with `UI_APP` and `CAPTAINSLOG_STORE_DIR`. The driver can't scroll or hover; a throwaway `CGEvent(scrollWheelEvent2Source:...)` helper posted at window coordinates scrolls. Window shots miss tooltips (separate windows). Sandboxes share the real app's settings, so to try a setting pass it as a launch argument (`open -n <app> --env CAPTAINSLOG_STORE_DIR=... --args -hiddenSidebarTabs '(todos, log)'`), which is never saved.

## Next

1. **Log: expanding an entry selects its whole title**, so a stray keystroke replaces it.
2. **Cards: the trash icon is always red**, which reads as danger. Use neutral icons; move delete to hover or the context menu.

## Small

4. **Secondary text is too faint**: role, attendees, activity counts, the PR repo line.
6. **Calendar: the grid opens scrolled to about 8:30**, clipping the "8 AM" label.
7. **Calendar: event blocks** are pale blue with grey text: low contrast.
8. **Todos: Upcoming's month groups** (November) show no date per todo.
9. **Todos: project pages repeat the title** in the toolbar and the header.
10. **Todos: the small grey icons after titles** (GitHub mark, doc, people) don't explain themselves.

## Medium

11. **PR cards: expanding one rearranges the header**: the title turns into a blue link and date and stats drop to a second line. Keep the header row fixed and add the body below. The "Notes" placeholder takes a line too. The author chip ("Alex Chen 1") hides that person's PRs, but nothing says so: label it ("Authors") or move it into the filter menu.
12. **Calendar: the list view is bare**: no day or week grouping, no sign of which meetings have notes or a summary.
13. **Todos: the list column is too narrow**; project names truncate ("Screening v2 mi…"). An expanded todo has no container, so edit mode is hard to see; Things raises a card with a shadow (a draft in a detail page's Todos box already reads as a white card).
14. **Search: type icons are small.** A type label, or grouping by type, would help a long result list.
15. **Interviews: the list could show whether the scorecard is submitted.**
16. **People: initials avatars** would help scanning the list.

## Large (decide before starting)

18. **Search as a Cmd-K palette** over any tab rather than a destination.
19. **Width is inconsistent.** Detail pages use a centred 760pt column; lists stretch full width, so PR and Log stats, dates and badges sit far from their titles.
20. Embedded Claude. A Claude window embedded with ghostty, with the skill loaded. So at any time we can quickly ask questions.

## Open questions

- **Slack copy and paste icons show no tooltip on hover**, on every notes box. `.help` is set (the accessibility tree shows it), and the review found them missing before the detail-page rework too. Synthetic hovers show no tooltip anywhere, so it needs a real hover: compare the Highlight flag with a notes box's copy icon. If only the copy icon fails, look at the native editor (`NativeMarkdownField`).
- **The agenda's faded past events and Now label** are untested on screen: the seed's today was a Sunday with nothing on.
