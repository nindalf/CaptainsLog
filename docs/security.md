# Security review

What Captain's Log touches, for a security review before colleagues install it. Each claim names the code that backs it, so you can check it. File references are from the repo root.

## What it is

A personal work log for macOS: a SwiftUI app, a `captains-log` CLI and Claude Code skills, all over one local SQLite store. Most people install the signed release through Homebrew; anyone can build it from source instead (see [Distribution and supply chain](#distribution-and-supply-chain)). There's no server and no shared backend. One user per install.

## Data it holds

| Data | Source | Stored |
|---|---|---|
| Calendar events: title, start and end, location, Meet link, attendee names and emails | Google Calendar, via `gws` | Yes. Event descriptions are not decoded or stored (`GCalEvent` in `Sources/CaptainsLogKit/Sync/CalendarSync.swift`). |
| Pull requests: number, title, body, state, author, reviewers, size, URL | GitHub, via `gh` | Yes, for the repos the user configures (`prFields` in `Sources/CaptainsLogKit/Sync/GitHubSync.swift`). |
| Meeting notes, transcripts, todos, projects, log entries | The user | Yes. |
| **Interview notes and scorecards** about candidates | The user | Yes. Personal data about non-employees. |
| **Feedback given and received** about colleagues | The user | Yes. Personal data about employees. |

The last two rows are the sensitive ones. They're the same notes people already keep in Notion or Google Docs, but here they sit in a local file instead.

## Where it lives

- **The store:** `~/Library/Application Support/CaptainsLog/CaptainsLog.store` (SQLite, through SwiftData), plus `sync-history.json` beside it (sync timestamps and error messages). `Store.directory` in `Sources/CaptainsLogKit/Store.swift`. The app doesn't encrypt the store itself; it relies on FileVault. macOS doesn't sync this folder to iCloud.
- **Settings:** UserDefaults, the app's `com.nindalf.captainslog` domain (`Sources/CaptainsLogKit/Settings.swift`; the CLI opens it as a suite). Repo names, calendar names, intervals. No credentials.
- **Backups:** `~/Google Drive/My Drive/CaptainsLog backups/`, in the user's work Google Drive. See [Backups](#backups).
- **Logs:** `os.Logger`, subsystem `com.nindalf.captainslog`. No interpolation is marked `privacy: .public`, so dynamic values (titles, names, errors) are redacted in the persisted unified log.

## External access

The app and CLI have no network code of their own: no `URLSession`, no sockets, no web views, no LLM calls. Everything external goes through one helper, `runProcess` (`Sources/CaptainsLogKit/Process/RunProcess.swift`), which runs a binary at a fixed path with arguments as an array (no shell, no string interpolation into commands). These are all its call sites:

| Binary | Arguments | Call site |
|---|---|---|
| `/opt/homebrew/bin/gh` | `pr list --repo R --author A --state S --limit 50 --json F` | `GitHubSync.fetchPRs` |
| `/opt/homebrew/bin/gh` | `pr list --repo R --search user-review-requested:@me --state open --limit 50 --json F` | `GitHubSync.syncReviewRequests` |
| `/opt/homebrew/bin/gh` | `pr view N --repo R --json F` | `GitHubSync.fetchPR` |
| `/opt/homebrew/bin/gws` | `calendar +agenda --days D --format json` | `CalendarSync.syncAllDayEvents` |
| `/opt/homebrew/bin/gws` | `calendar events list --params {timeMin, timeMax, singleEvents, ...}` | `CalendarSync` |
| `/bin/bash` | `backup.sh` or `backup-setup.sh`, bundled in the app | `Backup` in `Sources/CaptainsLogKit/Backup/Backup.swift` |

Every `gh` and `gws` call reads. Nothing in the code writes to GitHub or Calendar.

The only other outbound action is opening a URL in the default browser when the user clicks one (a PR, a document link, a link in their own notes), through `NSWorkspace.shared.open`.

## Credentials

The app never reads, stores or handles a credential. `gh` and `gws` keep their own tokens and are called as subprocesses. So the token's scopes, not the app's code, bound what a compromise of the app could do:

- **GitHub.** `gh auth login` grants `repo`, `read:org` and `gist` by default, which can write. The app only runs the read commands above. A fine-grained, read-only token through `GH_TOKEN` would cap this at the token level; it isn't tested or documented yet.
- **Google Calendar.** The setup guide (`docs/getting-started.md`) logs in with `gws auth login --readonly -s calendar`, which should grant only `calendar.readonly`. `gws` encrypts the token at rest, with the key in the macOS keychain. Check what a token actually holds with `gws auth status`: someone who logged in to `gws` for other reasons may already have broader scopes (full `calendar`, `gmail.modify`, `cloud-platform`), and the app would run with those.
- **The OAuth client is temporary.** For now each user creates a Desktop OAuth client in a Google Cloud project on their **personal** Google account, in Testing mode, and signs in to it with their work account. The client only identifies the app to Google: tokens and calendar data stay on the laptop, and the personal project's owner can't see them. But to the company's Google Workspace this is an unverified third-party app per person. A company-owned OAuth client, or an allowlisted one, would replace it.

## Backups

The app runs `Sources/CaptainsLogKit/Backup/backup.sh` once a day by default (hourly at most), and `just backup` runs it by hand:

1. `sqlite3 .backup` takes a consistent snapshot into a `mktemp -d` folder, deleted on exit, and checks it with `PRAGMA integrity_check`.
2. `tar -cJ` compresses it and `age -R recipient.txt` encrypts it to the user's X25519 public key. Plaintext never reaches Drive.
3. It writes the backup under a `.partial` name and renames it when complete, then prunes to the newest 30 (configurable).

`backup-setup.sh` creates the key pair once with `age-keygen`. The private key is encrypted with a passphrase the user chooses (`age -p`, scrypt) and saved beside the backups as `identity.age`. The unencrypted private key exists only in memory, and in a `mkfifo -m 600` pipe when the app drives the setup. Neither Google, Drive admins nor anyone else holding the folder can decrypt a backup without the passphrase. There's no recovery: a lost passphrase means lost backups.

`scripts/restore.sh` (`just restore`) is interactive only. It moves the current store aside instead of deleting it.

## Claude Code

The `captains-log` and `weekly-review` skills (`skills/`) let Claude Code read and write the store through the CLI. This is the one path by which store contents leave the laptop. **When Claude reads a record, that record is sent to Anthropic as part of the conversation**, under whatever terms the company's Claude Code use already has. The app does nothing with Claude on its own; this only happens when the user asks Claude something.

- Read commands are pre-approved in the skills' `allowed-tools` (`list`, `show`, `search`, `feed`, `status`, plus `jq`). Every write prompts the user first.
- The skills tell Claude not to look outside the store (no git, GitHub, Slack or web), and not to run destructive commands (`delete --permanently`, `empty-trash`, `people merge --yes`) unless the user asks for that one action.
- Records can be marked private (`isPrivate`), meaning the user wants them kept out of anything shared. It isn't access control: the store is single-user, and the CLI returns every record.

## Distribution and supply chain

- **The release.** `just release` (`justfile`) builds one zip from a tagged commit on the maintainer's Mac and publishes it as a GitHub release. The zip holds the app, with the CLI at `Contents/Helpers/captains-log` and the committed skills in `Contents/Resources/skills/`. The app and the CLI are signed with the maintainer's Developer ID (team `78T545JWUD`) with hardened runtime and no entitlements, then notarised by Apple, with the ticket stapled to the app. Check an installed copy with `spctl --assess -vv "/Applications/Captain's Log.app"`, and `codesign -dv --verbose=2` on the app and on `Contents/Helpers/captains-log`.
- **Homebrew.** The cask downloads that zip, checks its SHA-256, installs the app to `/Applications`, and links the CLI into Homebrew's `bin` and the skills into `~/.claude/skills`. No install scripts are fetched from the network.
- **Checking a release against its source.** Notarisation is Apple's automated malware scan, not a review of what the code does. What ties a release to the code is that it's reproducible: `just verify-release 1.2.3` downloads the release, rebuilds the tag with the tag's own build step (`_release-assemble`, which `release-build` uses too) and diffs the two. Both builds run at the same path, `/tmp/captainslog-release`, because the linker hashes build paths into each binary's UUID. The diff sets aside only what can't match: every binary's signature is replaced with the same ad hoc one, the stapled ticket is dropped, and `BuildMachineOSBuild` is removed from the `Info.plist` files. It needs the Xcode build the release names (`DTXcodeBuild` in its `Info.plist`). An empty diff means the release is exactly the tagged code, so review at the tag (`git checkout v1.2.3`). Releases before reproducible builds (v0.4.0 and earlier) can't be verified. Building from source (`docs/getting-started.md`) also runs exactly what you reviewed; that build is signed with your own development certificate, without hardened runtime, and isn't notarised.
- All the code it runs is the repo's own, Apple's system frameworks and three Apple-maintained open-source packages. The frameworks: Foundation, SwiftUI, AppKit, SwiftData, `os` for logging, and Carbon for the global quick-entry hotkey (`GlobalHotKey.swift`).
- The packages, all on tagged releases (`Package.swift`): `apple/swift-argument-parser` from 1.5.0, for the CLI's arguments only; `apple/swift-markdown` from 0.9.0, to parse notes; and `swiftlang/swift-cmark` 0.9.0, the C parser swift-markdown is built on. Both lockfiles are committed (`Package.resolved`, and Xcode's in `captainslog/captainslog.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`), so a build uses the reviewed versions; release builds refuse to resolve anything else. Updating a dependency is a commit.
- No iCloud or CloudKit. The app has no entitlements file, and SwiftData only syncs through CloudKit when the app has the iCloud entitlement (`ModelConfiguration` in `Store.swift`).
- Homebrew tools it relies on: `gh`, `googleworkspace-cli` (the `gws` binary; not Homebrew's unrelated `gws` formula), `age`, `just`.
- The app has no App Sandbox (`ENABLE_APP_SANDBOX = NO`): it has to run `gh`, `gws` and the backup scripts.

## Open items

- The Homebrew cask doesn't exist yet. The repo is private, so it needs a download strategy that authenticates to GitHub, or a public repo.

- A company-owned or allowlisted OAuth client in place of per-person personal-account projects.
- Find `gh` and `gws` on `PATH` instead of hardcoding `/opt/homebrew/bin` (`GitHubSync.swift:7`, `CalendarSync.swift:7`).

## Checking it yourself

A prompt to paste into Claude Code from the repo root:

```
Security-review this repo before I install and run it. It claims to only read
from GitHub (via gh) and Google Calendar (via gws), never write to any external
system, make no network calls of its own, call no LLMs, and write only to
~/Library/Application Support/CaptainsLog, its own UserDefaults, and age-encrypted
backups in ~/Google Drive/My Drive/CaptainsLog backups.
Verify each claim: find every subprocess, network call, file write and
credential access, in the app (captainslog/), the shared package
(Sources/CaptainsLogKit/), the CLI (Sources/captains-log/), the justfile and
scripts/. Report anything that contradicts the claims or surprises you.
```

To spot-check by hand:

```sh
grep -rn 'runProcess(\|Process()' Sources captainslog
grep -rn 'URLSession\|URLRequest\|WKWebView\|import Network' Sources captainslog
grep -rn 'NSWorkspace' captainslog
```
