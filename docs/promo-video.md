# Promo video plan

A short video of the app in use that makes people want to install it. Footage is the real app
on demo data. Nothing is generated except music, voice and decoration.

## Outputs

One edit, two Remotion compositions sharing the same clips:

- **Loop** (20-30s, silent, captions burned in): for the README and the Homebrew/GitHub pages.
  MP4 plus a small GIF fallback. It has to make sense muted and from any frame.
- **Full** (60-90s, music, optional voiceover, captions): for YouTube and X. 1920x1080, plus
  a 1080x1080 crop for X if the framing allows.

## The pitch

The alternative people use is Claude plus flat files. It works, but Claude does every
interaction: finding the relevant note, keeping notes up to date, listing what's open. Each of
those is slow and costs tokens.

The message is **Claude where it helps, instant everywhere else**:
- The UI is fast and has what you need in view: today's meetings, open PRs, reviews waiting,
  open todos.
- Search filters as you type, with no model call.
- Adding a todo takes a keystroke (Quick Entry, Control-Space).
- Reading and searching your own work costs nothing. Claude is for the parts that need it:
  answering questions across your notes and writing up the week.

This runs through the video as a thread. It is not a comparison segment. Show it, don't argue
it: let search filter instantly on screen and put a small caption on it ("No tokens. No wait.").
The rest of the video features Claude Code, so don't knock Claude. Keep the claims exact: the
app and CLI cost nothing, Claude costs whatever your plan does. If a speed number appears on
screen, measure it first.

## Storyboard (full cut)

1. **Hook (0-6s).** "Your week is spread across GitHub, Calendar, Notion and Slack." Quick cuts
   of those logos or tabs collapse into the Captain's Log window.
2. **Morning dashboard (6-18s).** Today's meetings, my PRs, reviews waiting, today's todos.
   Slow zoom into each region with a caption.
3. **Quick Entry (18-28s).** In another app (a browser or editor), Control-Space opens the
   panel. Type a todo with an @person and a date, Return, gone. Cut to the todo already in the
   app. Caption: "From anywhere, in one keystroke."
4. **Search (28-36s).** Type into "Search everything"; results narrow on every keystroke.
   Caption: "Instant. No tokens."
5. **Notes that link up (36-48s).** A todo tagged with a colleague shows on their page and in
   the next 1:1 with them. Their page: feedback, PRs, meetings.
6. **Claude Code (48-70s).** In a terminal on the demo store: "What did we decide about the
   promotions migration?" answered from the notes, then a short `/weekly-review` excerpt
   producing brag-doc entries. Speed the waiting up 2-4x and label it.
7. **Close (70-80s).** "Native. Local. Your data." Then `brew install --cask
   nindalf/tap/captains-log` and an end card.

**Loop cut:** beats 2, 3, 4 and 6 only, about 6s each, with a caption on each. It ends on the
dashboard so the loop is seamless.

Demo-data hooks: the company is Larder (grocery delivery). "Promotions engine migration" is a
project with weekly "Promotions migration sync" meetings
(`Sources/captains-log/SeedDemoCalendar.swift`), which makes a good Claude question. Check what
the seeded notes actually say before scripting the question.

## Capture

- Use the private sandbox: `just ui-build`, `just ui-private-seed`, `just ui-private launch`.
  The user has OK'd Claude driving the screen for this, so stay off it except while recording.
- Record the window with ScreenCaptureKit at 2x (the API `scripts/ui.swift`'s `shot` already
  uses), as a separate small recorder script, or `screencapture -v` as a fallback. Record each
  beat as its own clip, and do retakes per beat.
- The driver's clicks make the cursor jump straight to each point. Either add eased mouse moves
  before each click (interpolated `mouseMoved` events, like `dragCommand` does) or hide the
  real cursor and draw one in Remotion from logged click coordinates. Eased real moves are
  simpler, so try them first.
- Before recording: Do Not Disturb on, menu bar clean, a neutral wallpaper, the window at a fixed
  size and position, and light mode. Decide on light or dark once and keep it for every clip.
- No scrolling in the driver. Use the CGEvent scroll helper (see the UI driver notes in memory)
  or choose views that fit.

### Quick Entry

The capture traps are here:
- Control-Space is global. **Quit the real app** first, or it holds the hotkey. Things 3 also
  binds Control-Space, so quit it too.
- `quickEntryEnabled` lives in the real `com.nindalf.captainslog` defaults (sandboxes share
  them). Read it before the take, enable it if needed, and restore it afterwards.
- The panel is a separate window. A window-only capture misses it, so record the display (or a
  region) for this beat.
- Synthetic typing doesn't reach a new todo draft's title in the main window. Check whether it
  reaches the Quick Entry field. If it doesn't, the user types this take while the recorder
  runs.

### Claude Code segment

- Run `claude` from a temp directory outside the repo with
  `CAPTAINSLOG_STORE_DIR=.build/ui-claude/store`, as `just demo` does for the user's sandbox, so
  it doesn't load this project's CLAUDE.md or memory.
- Large terminal font, a clean prompt, a fixed window size. Real answers only, no faked output.

## Editing (Remotion)

- A separate `promo/` folder with its own `package.json`, outside the Swift build. Commit the
  source but not the clips or renders (`promo/clips/`, `promo/out/` in `.gitignore`).
- Compositions `Loop` and `Full` share one beat list (clip, trim, zoom region, caption).
- Text style: the system font (SF Pro), short captions, large enough to read on a phone.

## Delegated to OpenRouter models

`OPENROUTER_API_KEY` is in the environment. Check the model list before each run, since the IDs
change.

| Job | Model | Notes |
|---|---|---|
| Review the rendered cut | `google/gemini-3.5-flash`, `google/gemini-3.1-pro-preview` for a final pass | They take video and audio input. Ask for timestamped notes: dead air, unreadable text, caption timing, pacing, the first 3 seconds. Iterate on its notes. |
| Music | `google/lyria-3-pro-preview` | Upbeat but calm, no vocals, sized to the full cut. Check the licence before posting. |
| Voiceover (optional) | `openai/gpt-audio` | Only if captions alone feel thin. The loop has no audio. |
| Thumbnail / end-card background | `google/gemini-3-pro-image` or `openai/gpt-5.4-image-2` | Decoration only, never fake UI. |

Not delegated: the script, the storyboard, capture, the Remotion edit, or generated app footage.

## Checklist

1. Read the seeded data and script exact actions and captions for each beat.
2. Build the recorder and eased-cursor support. Do a test take of one beat.
3. Prepare the screen (real app and Things quit, DND on), then record every beat.
4. Quick Entry take: check synthetic typing, or hand the take to the user.
5. Claude Code take.
6. Set up `promo/` with Remotion, cut the Full version, then the Loop.
7. Music from Lyria, then a Gemini review pass, fixes, a second review.
8. Render both formats and restore any defaults changed for capture.
