import ArgumentParser

@main
struct CaptainsLog: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "captains-log",
        abstract: "Personal work tracking CLI",
        version: cliVersion,
        subcommands: [Show.self, Status.self, Whoami.self, Log.self, FeedCommand.self, Search.self, Meetings.self, PRs.self, Todos.self, Projects.self, People.self, Events.self, Interviews.self, Sync.self, BackupCommand.self, BackupSetup.self, Restore.self, SkillsCommand.self, SeedDemo.self]
    )
}
