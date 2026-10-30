# Getting started

From a fresh Mac to your first weekly review, in order.

## 0. Prerequisites

- An Apple Silicon Mac on macOS 26.2 or later, with **Xcode** from the App Store. The Command Line Tools alone can't build the app. Open Xcode once so it installs its components.
- **[Homebrew](https://brew.sh)**, then:
  ```sh
  brew install just gh googleworkspace-cli age
  ```
  Use `googleworkspace-cli`, not `brew install gws`: that's an unrelated tool with the same name.
- **Google Drive for desktop**, signed in with your work account (SSO), so `~/Google Drive` exists. Backups go there.
- **Claude Code**, logged in.

Clone the repo and run everything below from its root.

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

## 3. Build and install

```sh
just check-tools        # gh, gws, age, claude, swift, xcodebuild; xcbeautify is only for tests
just install-app        # builds a Release copy and installs it to /Applications
just install-cli        # builds the CLI and links it to /opt/homebrew/bin/captains-log
just install-skills     # links the Claude Code skills into ~/.claude/skills
```

`just install-app` uses `sudo` only to copy the app into `/Applications`, if your account can't write there. Grant yourself admin with the Privileges app first. Don't run the whole recipe with `sudo`: the build folder would end up owned by root.

Rerun the last three after pulling changes.

Open **Captain's Log** from `/Applications`, then in **Settings**:
- **GitHub Repos**: the repos to sync, as `owner/name` (e.g. `your-org/your-repo`).
- **Calendar Allowlist**: the calendars worth showing. Leave it empty for all of them.

Click **Sync** in the menu bar. Within a minute the dashboard shows today's meetings and your PRs; a sync error shows in the menu bar.

## 4. Backups

Your data is one SQLite file on this Mac, so set up backups before you write anything in it. In **Settings → Backups**, click **Set Up Backups** and follow the steps. It checks for Google Drive and `age`, then asks for a passphrase.

**Pick a passphrase you won't lose, and store it in your password manager.** It's the only way to open your backups. Forget it and every backup is unreadable; nobody can recover it.

Then click **Back Up Now** and check **Last backup** updates. From then on the app backs up once a day (change it under **Back up every**) into `~/Google Drive/My Drive/CaptainsLog backups/`.

The terminal equivalents are `just backup-setup`, then `just backup`. `just restore` brings a backup back; the README's "Your data" explains how.

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
