# Edit this in github.com/nindalf/CaptainsLog (homebrew/captains-log.rb). `just release` sets version and
# sha256 there and publishes it to github.com/nindalf/homebrew-tap
cask "captains-log" do
  version "0.7.1"
  sha256 "ea2e861a5f61d8c702f78c9cf30ca404e807d9c207f6c87426ab4cc7ed9a5e28"

  url "https://github.com/nindalf/CaptainsLog/releases/download/v#{version}/CaptainsLog-#{version}.zip"
  name "Captain's Log"
  desc "Local work log: meetings, todos, pull requests and calendar in one place"
  homepage "https://github.com/nindalf/CaptainsLog"

  # The CLI is built for Apple silicon only
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Captain's Log.app"
  binary "#{appdir}/Captain's Log.app/Contents/Helpers/captains-log"

  # Links the bundled skills for Claude Code (~/.claude/skills) and for Codex and other agents
  # (~/.agents/skills). Steps run sandboxed and can write only their own folder, so neither creates a
  # missing ~/.claude or ~/.agents: an agent that isn't set up is skipped
  postflight_steps do
    run "Captain's Log.app/Contents/Helpers/captains-log", base: :appdir,
        args: ["skills", "install", "--agent", "claude"], must_succeed: false, print_stderr: false,
        writable_paths: [".claude/skills"], writable_base: :home
    run "Captain's Log.app/Contents/Helpers/captains-log", base: :appdir,
        args: ["skills", "install", "--agent", "codex"], must_succeed: false, print_stderr: false,
        writable_paths: [".agents/skills"], writable_base: :home
  end

  uninstall_preflight_steps do
    run "Captain's Log.app/Contents/Helpers/captains-log", base: :appdir,
        args: ["skills", "uninstall"], must_succeed: false,
        writable_paths: [".claude/skills", ".agents/skills"], writable_base: :home
  end

  uninstall quit: "com.nindalf.captainslog"

  caveats <<~EOS
    The skills are linked for Claude Code if ~/.claude existed at install, and into
    ~/.agents/skills (for Codex) if ~/.agents did. To link them after setting up an agent:
      captains-log skills install
  EOS

  # No zap: the store in ~/Library/Application Support/CaptainsLog is the user's data, and stays
end
