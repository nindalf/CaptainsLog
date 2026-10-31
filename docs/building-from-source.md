# Building from source

To build from source you'll need an Apple Silicon Mac on macOS 26.2 or later along with Xcode.

```sh
brew install just
just check-tools        # gh, gws, age, claude, swift, xcodebuild; xcbeautify is only for tests
just install-app        # builds the app and CLI, installs them to /Applications, links the CLI and skills
```

`just install-app` builds what a release holds, from your working tree, uncommitted changes included: the app, with the CLI in `Contents/Helpers` and the skills in `Contents/Resources/skills`. It links `/opt/homebrew/bin/captains-log` and the skills to that copy, as Homebrew does, so it can replace a Homebrew install and `brew upgrade` can replace it back. It signs with your Developer ID if you have one, which keeps Keychain and privacy permissions from being asked again after each rebuild, and ad hoc otherwise. It doesn't notarize: a build made on your Mac isn't quarantined, so Gatekeeper lets it run.

It uses `sudo` only to copy the app into `/Applications`, if your account can't write there. Grant yourself admin with the Privileges app first. Don't run the whole recipe with `sudo`: the build folder would end up owned by root.

Rerun it after pulling or making changes.
