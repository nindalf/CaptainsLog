import CaptainsLogKit
import Foundation
import Testing

struct SkillsTests {
    let fm = FileManager.default

    /// A fresh home folder and a stand-in app bundling the given skills.
    func setUp(skills: [String] = ["captains-log", "weekly-review"]) throws -> (home: URL, bundled: URL) {
        let root = fm.temporaryDirectory.appending(path: "SkillsTests-\(UUID().uuidString)")
        let home = root.appending(path: "home")
        let bundled = root.appending(path: "Captain's Log.app/Contents/Resources/skills")
        for skill in skills {
            try fm.createDirectory(at: bundled.appending(path: skill), withIntermediateDirectories: true)
            try Data("---\nname: \(skill)\n---\n".utf8).write(to: bundled.appending(path: "\(skill)/SKILL.md"))
        }
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        return (home, bundled)
    }

    func destination(_ url: URL) -> String? {
        try? fm.destinationOfSymbolicLink(atPath: url.path(percentEncoded: false))
    }

    @Test func installsOnlyForAgentsThatAreSetUp() throws {
        let (home, bundled) = try setUp()
        try fm.createDirectory(at: home.appending(path: ".codex"), withIntermediateDirectories: true)
        let links = try Skills.install(bundled: bundled, home: home, environment: [:])
        #expect(links.map(\.agent) == [.codex, .codex])
        #expect(links.allSatisfy { $0.state == .linked })
        // Codex reads the cross-agent folder, not ~/.codex
        #expect(destination(home.appending(path: ".agents/skills/weekly-review")) == bundled.appending(path: "weekly-review").path(percentEncoded: false))
        #expect(!fm.fileExists(atPath: home.appending(path: ".claude").path(percentEncoded: false)))
    }

    @Test func refusesWhenNoAgentIsSetUp() throws {
        let (home, bundled) = try setUp()
        #expect(throws: SkillsError.self) { try Skills.install(bundled: bundled, home: home, environment: [:]) }
    }

    @Test func honoursConfigDirectoryOverrides() throws {
        let (home, bundled) = try setUp()
        let claude = home.appending(path: "elsewhere/claude")
        try fm.createDirectory(at: claude, withIntermediateDirectories: true)
        _ = try Skills.install(bundled: bundled, home: home, environment: ["CLAUDE_CONFIG_DIR": claude.path(percentEncoded: false)])
        #expect(destination(claude.appending(path: "skills/captains-log")) != nil)
    }

    @Test func removesLinksToSkillsTheAppNoLongerShips() throws {
        let (home, bundled) = try setUp(skills: ["captains-log", "old-skill"])
        try fm.createDirectory(at: home.appending(path: ".claude"), withIntermediateDirectories: true)
        _ = try Skills.install(bundled: bundled, home: home, environment: [:])
        try fm.removeItem(at: bundled.appending(path: "old-skill"))
        _ = try Skills.install(bundled: bundled, home: home, environment: [:])
        let names = try fm.contentsOfDirectory(atPath: home.appending(path: ".claude/skills").path(percentEncoded: false))
        #expect(names == ["captains-log"])
    }

    @Test func uninstallRemovesOnlyItsOwnLinksDanglingIncluded() throws {
        let (home, bundled) = try setUp()
        try fm.createDirectory(at: home.appending(path: ".claude"), withIntermediateDirectories: true)
        _ = try Skills.install(bundled: bundled, home: home, environment: [:])
        let dir = home.appending(path: ".claude/skills")
        try fm.createSymbolicLink(at: dir.appending(path: "checkout"), withDestinationURL: home)
        try fm.createDirectory(at: dir.appending(path: "mine"), withIntermediateDirectories: true)
        // The app was deleted without uninstalling: its links dangle
        try fm.removeItem(at: bundled)
        let removed = try Skills.uninstall(home: home, environment: [:])
        #expect(removed.count == 2)
        #expect(try fm.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).sorted() == ["checkout", "mine"])
    }

    @Test func findsTheBundleThroughHomebrewsLink() throws {
        let (home, bundled) = try setUp()
        let helpers = bundled.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Helpers")
        try fm.createDirectory(at: helpers, withIntermediateDirectories: true)
        let executable = helpers.appending(path: "captains-log")
        try Data().write(to: executable)
        let brewLink = home.appending(path: "captains-log")
        try fm.createSymbolicLink(at: brewLink, withDestinationURL: executable)
        let found = try Skills.bundledDirectory(forExecutable: brewLink)
        #expect(found.resolvingSymlinksInPath() == bundled.resolvingSymlinksInPath())
        #expect(throws: SkillsError.self) { try Skills.bundledDirectory(forExecutable: home.appending(path: "nowhere")) }
    }
}
