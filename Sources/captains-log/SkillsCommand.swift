import ArgumentParser
import CaptainsLogKit
import Foundation

struct SkillsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skills",
        abstract: "Link the app's bundled skills into Claude Code and Codex",
        discussion: "Claude Code reads ~/.claude/skills (or $CLAUDE_CONFIG_DIR/skills), Codex ~/.agents/skills. The links point into Captain's Log.app, so upgrading the app updates the skills. Only works for the CLI inside the app; in a checkout, run `just install-skills`.",
        subcommands: [Status.self, Install.self, Uninstall.self]
    )

    static func bundled() throws -> URL {
        guard let executable = Bundle.main.executableURL else { throw ValidationError("Can't find this executable's path") }
        do { return try Skills.bundledDirectory(forExecutable: executable) } catch { throw ValidationError(error.localizedDescription) }
    }

    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// The account's home, not $HOME: Homebrew's install steps point $HOME at a scratch folder.
    static var home: URL { .homeDirectory }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Each bundled skill's link, for every agent that's set up",
            discussion: "state is linked, missing, stale (points into a Captain's Log app, but not this one), foreign (a link elsewhere, such as a checkout) or folder."
        )

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            try printJSON(Skills.status(bundled: SkillsCommand.bundled(), home: SkillsCommand.home, environment: SkillsCommand.environment), pretty: pretty)
        }
    }

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Link the bundled skills for every agent that's set up",
            discussion: "Links that already point into a Captain's Log app are updated. A link elsewhere is left alone unless you pass --force; a real folder always is. Links to skills the app no longer ships are removed."
        )

        @Option(name: .long, help: "Install for this agent only, even if it isn't set up yet: claude or codex. Repeatable")
        var agent: [Skills.Agent] = []

        @Flag(name: .long, help: "Also replace links that point somewhere else, such as a checkout")
        var force: Bool = false

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            let links: [Skills.Link]
            do {
                links = try Skills.install(
                    bundled: SkillsCommand.bundled(), home: SkillsCommand.home, environment: SkillsCommand.environment,
                    agents: agent.isEmpty ? nil : agent, force: force)
            } catch let error as SkillsError {
                throw ValidationError(error.localizedDescription)
            }
            try printJSON(links, pretty: pretty)
        }
    }

    struct Uninstall: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove the links that point into a Captain's Log app",
            discussion: "Other links and folders are left alone. Prints the paths removed."
        )

        @Flag(name: .long, help: "Pretty-print JSON output")
        var pretty: Bool = false

        mutating func run() async throws {
            try printJSON(Skills.uninstall(home: SkillsCommand.home, environment: SkillsCommand.environment), pretty: pretty)
        }
    }
}

extension Skills.Agent: ExpressibleByArgument {}
