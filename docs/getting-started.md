# Getting started

From a fresh Mac to your first weekly review, in order.

## 0. Prerequisites

- An Apple Silicon Mac on macOS 26.2 or later. To build from source, also **Xcode** from the App Store: the Command Line Tools alone can't build the app. Open Xcode once so it installs its components.
- **[Homebrew](https://brew.sh)**, then:
  ```sh
  brew install gh googleworkspace-cli age
  ```
  Use `googleworkspace-cli`, not `brew install gws`: that's an unrelated tool with the same name. Add `just` if you'll build from source.
- **Google Drive for desktop**, signed in with your work account (SSO), so `~/Google Drive` exists. Backups go there.
- **Claude Code**, logged in.

## 1. Google Calendar: `gws`

`gws` needs an OAuth client to log in with. For now you create one in a Google Cloud project on your **personal** Google account, then sign in to it with your **work** account. `gws auth setup` would create one, but it needs `gcloud`; doing it by hand in the Cloud Console is quicker:

1. Go to [console.cloud.google.com](https://console.cloud.google.com), signed in with your personal account, and create a project (e.g. `captains-log`).
2. **APIs & Services → Library**: enable the **Google Calendar API**.
3. **APIs & Services → OAuth consent screen**: user type **External**, leave it in **Testing**. Fill in the app name and your personal email where it asks.
4. **Test users → Add users**: add your **work** email. Skip this and login fails with "Access blocked".
5. **APIs & Services → Credentials → Create credentials → OAuth client ID**, type **Desktop app**. Any other type fails with `redirect_uri_mismatch`.
6. Download the client JSON and save it as `~/.config/gws/client_secret.json`:
   ```sh
   mkdir -p ~/.config/gws && mv ~/Downloads/client_secret_*.json ~/.config/gws/client_secret.json
   ```
7. Log in, read-only, calendar only. A browser opens: pick your **work** account. Google warns the app isn't verified; it's yours, so **Continue**.
   ```sh
   gws auth login --readonly -s calendar
   ```
8. Check it works:
   ```sh
   gws calendar +agenda --days 1
   ```
   That should list today's meetings. A 403 with `accessNotConfigured` means step 2 didn't take: open the link it prints, enable the API, wait a few seconds and retry.

The OAuth client only identifies the app to Google. Your calendar data comes from your work account and stays on your Mac. `gws` keeps its token encrypted, with the key in your keychain.

## 2. GitHub: `gh`

```sh
gh auth login
```

Pick GitHub.com, HTTPS, and log in with a browser. If your company's org asks you to authorise SSO for the token, do it. Check you can see PRs in a repo you work in:

```sh
gh pr list -R your-org/your-repo --limit 3
```

## 3. Install

Install with Homebrew. This is the recommended way:

```sh
brew install --cask nindalf/tap/captains-log
```

That installs the app to `/Applications`, puts `captains-log` on your PATH, and links the skills into `~/.claude/skills`, and into `~/.agents/skills` for Codex if `~/.agents` exists. `brew upgrade` updates all three. If you set up Claude Code or Codex later, run `captains-log skills install`. Switching from a source install: delete `/opt/homebrew/bin/captains-log` and the app first, since Homebrew won't replace files it didn't install.

### From source

Build from source instead if you want to run exactly the code you reviewed, or to change it. You need Xcode and `just` (see Prerequisites). In a clone of the repo:

```sh
just check-tools        # gh, gws, age, claude, swift, xcodebuild; xcbeautify is only for tests
just install-app        # builds the app and CLI, installs them to /Applications, links the CLI and skills
```

`just install-app` builds what a release holds, from your working tree, uncommitted changes included: the app, with the CLI in `Contents/Helpers` and the skills in `Contents/Resources/skills`. It links `/opt/homebrew/bin/captains-log` and the skills to that copy, as Homebrew does, so it can replace a Homebrew install and `brew upgrade` can replace it back. It signs with your Developer ID if you have one, which keeps Keychain and privacy permissions from being asked again after each rebuild, and ad hoc otherwise. It doesn't notarize: a build made on your Mac isn't quarantined, so Gatekeeper lets it run.

It uses `sudo` only to copy the app into `/Applications`, if your account can't write there. Grant yourself admin with the Privileges app first. Don't run the whole recipe with `sudo`: the build folder would end up owned by root.

Rerun it after pulling or making changes.

### Then

Open **Captain's Log** from `/Applications`, then in **Settings**:
- **GitHub Repos**: the repos to sync, as `owner/name` (e.g. `your-org/your-repo`).
- **Calendar Allowlist**: the calendars worth showing. Leave it empty for all of them.

Click **Sync** in the menu bar. Within a minute the dashboard shows today's meetings and your PRs; a sync error shows in the menu bar.

## 4. Backups

Your data is one SQLite file on this Mac, so set up backups before you write anything in it. In **Settings → Backups**, click **Set Up Backups** and follow the steps. It checks for Google Drive and `age`, then asks for a passphrase.

**Pick a passphrase you won't lose, and store it in your password manager.** It's the only way to open your backups. Forget it and every backup is unreadable; nobody can recover it.

Then click **Back Up Now** and check **Last backup** updates. From then on the app backs up once a day (change it under **Back up every**) into `~/Google Drive/My Drive/CaptainsLog backups/`.

`captains-log backup` takes one from the terminal, and `captains-log restore` brings one back; the README's "Your data" explains how. `captains-log backup-setup` does the setup from the terminal instead of Settings.

## 5. Your team

If someone has shared your teammates' details in a JSON file (their GitHub and Slack handles), import it one of two ways:
- In the app: **People → Roster → Import Roster…**, check the preview, then **Import**.
- In the terminal: `captains-log people import roster.json` previews it; add `--yes` to apply.

## 6. First weekly review

Open Claude Code in any folder and run:

```
/weekly-review
```

The first time, there are no goals in your store, so it asks for them before anything else: your goals for the half, and the progression framework signals you're working towards. Paste them in, and it saves them as a private log entry tagged `goals`. Every later review maps your work onto them. To change them, ask Claude to update your goals, or edit the entry in the app's Log.

It then reads your week, interviews you about it, and saves brag-doc entries back to the log. The first week is thin, since only GitHub and Calendar have synced; the reviews get better as you keep meeting notes and todos in the app.

Run it every Friday. Between reviews, ask Claude things like "what's on my plate today?" or "what did Priya and I decide about the migration?". The `captains-log` skill answers from your store.
