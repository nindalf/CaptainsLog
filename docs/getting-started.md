# Getting started

From a fresh Mac to your first weekly review, in order.

## 1. Install

```sh
brew install --cask nindalf/tap/captains-log
```

- Installs the `Captain's Log.app` to `/Applications`
- Puts the `captains-log` CLI on your PATH
- Links the skills into `~/.claude/skills`, and into `~/.agents/skills` for Codex if `~/.agents` exists. `

`brew upgrade` updates all three at once. No other command is needed.

Then install the tools that Captain's Log uses to pull info and store backups.

  ```sh
  brew install gh                  # Github
  brew install googleworkspace-cli # Calendar. Don't brew install gws, that's an unrelated tool
  brew install google-drive        # To store backups. Sign in with your work account (SSO), so `~/Google Drive` exists.
  brew install age                 # for encrypting backups
  ```

## 2. Set up calendar

`gws` needs an OAuth client to log in with. Your company provides one: a Desktop app client in its own Google Cloud project, internal to the company's Workspace and limited to `calendar.readonly`. You don't create anything; you only need its client ID and secret.

1. Log in, read-only, calendar only, passing the company's client ID and secret. A browser opens: pick your **work** account. A personal account fails with "Access blocked", since the client only accepts accounts in the company.
   ```sh
   GOOGLE_WORKSPACE_CLI_CLIENT_ID=<client-id> \
   GOOGLE_WORKSPACE_CLI_CLIENT_SECRET=<client-secret> \
   gws auth login --readonly -s calendar
   ```
   `gws` saves the client with your token, so you only pass them this once.
2. Check it works:
   ```sh
   gws calendar +agenda --days 1
   ```
   That should list today's meetings. A 403 with `accessNotConfigured` means the Calendar API isn't enabled in the company's project: tell whoever runs it.

The OAuth client only identifies the app to Google. Your calendar data comes from your work account and stays on your Mac; the project's owners can't see your token or your calendar. `gws` keeps its token encrypted, with the key in your keychain.

## 2. Set up Github

1. Log in
```sh
gh auth login # Pick GitHub.com, HTTPS, and log in with a browser.
```
2. Check it works:
```sh
gh pr list -R your-org/your-repo --limit 3
```

## 3. Import team

If someone has shared your teammates' details in a JSON file (their GitHub and Slack handles), import it one of two ways:
- In the app: **People → Roster → Import Roster…**, check the preview, then **Import**.
- In the terminal: `captains-log people import roster.json` previews it; add `--yes` to apply.

Or enter their Slack and Github handles manually.

## 4. First weekly review

Open Claude Code in any folder and run `/weekly-review`.

The first time Claude will ask for your goals for the half, and the progression framework signals you're working towards. Every later review maps your work onto them. To change them, ask Claude to update your goals, or edit the entry in the app's Log.

Run `/weekly-review` every Friday. It then reads your week, interviews you about it, and saves brag-doc entries back to the log. The first week is thin, since only GitHub and Calendar have synced; the reviews get better as you keep meeting notes and todos in the app.

 Between reviews, ask Claude things like "what's on my plate today?" or "what did Priya and I decide about the migration?". 

## 5. Backups

Your data is one SQLite file on your Mac. To set up encrypted backups to Google Drive, follow these steps.

- In **Settings → Backups**, click **Set Up Backups**.
- Pick a passphrase you won't lose, and store it in your password manager. It's the only way to open your backups. Forget it and every backup is unreadable; nobody can recover it.
- Click **Back Up Now**. You backup will appear in `~/Google Drive/My Drive/CaptainsLog backups/`.

To restore: run `captains-log restore` from the CLI.
