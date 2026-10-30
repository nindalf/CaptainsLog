import Foundation

public enum SkillsError: Error, LocalizedError {
    case notInAppBundle(String)
    case noAgents

    public var errorDescription: String? {
        switch self {
        case .notInAppBundle(let path):
            "\(path) isn't inside Captain's Log.app, so there are no bundled skills to link. In a checkout, run `just install-skills`"
        case .noAgents: "Neither Claude Code nor Codex is set up for this user"
        }
    }
}

/// Links the skills bundled in the app (`Contents/Resources/skills`) into the folders where agents look
/// for them. Links point into the app, so an upgrade updates the skills. Only links into a Captain's Log
/// app are ever replaced or removed: a checkout's links and real folders are left alone.
public enum Skills {
    public enum Agent: String, CaseIterable, Codable, Sendable {
        case claude, codex

        /// The folder that exists once the agent has been set up.
        public func home(in home: URL, environment: [String: String]) -> URL {
            switch self {
            case .claude: environment["CLAUDE_CONFIG_DIR"].map { URL(filePath: $0) } ?? home.appending(path: ".claude")
            case .codex: environment["CODEX_HOME"].map { URL(filePath: $0) } ?? home.appending(path: ".codex")
            }
        }

        public func skillsDirectory(in home: URL, environment: [String: String]) -> URL {
            switch self {
            case .claude: self.home(in: home, environment: environment).appending(path: "skills")
            // Codex reads user skills from the cross-agent folder, not its own
            case .codex: home.appending(path: ".agents/skills")
            }
        }

        public func isSetUp(in home: URL, environment: [String: String]) -> Bool {
            FileManager.default.fileExists(atPath: self.home(in: home, environment: environment).path(percentEncoded: false))
        }
    }

    public struct Link: Equatable, Encodable, Sendable {
        public enum State: String, Encodable, Sendable {
            /// Points at this app's copy.
            case linked
            case missing
            /// Points into a Captain's Log app, but not this copy: the app moved, or the link dangles.
            case stale
            /// A link to somewhere else, such as a checkout's `skills/`.
            case foreign
            /// A real file or folder.
            case folder
        }

        public let agent: Agent
        public let skill: String
        public let path: String
        public let state: State
        public let destination: String?
    }

    /// The marker for links this installer owns.
    static let bundlePathComponent = "/Captain's Log.app/Contents/Resources/skills/"

    /// The skills beside an executable in `Contents/Helpers`, after resolving symlinks such as Homebrew's.
    public static func bundledDirectory(forExecutable executable: URL) throws -> URL {
        let resolved = executable.resolvingSymlinksInPath()
        let dir = resolved.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources/skills")
        let path = dir.path(percentEncoded: false) + "/"
        guard path.contains(bundlePathComponent), FileManager.default.fileExists(atPath: path) else {
            throw SkillsError.notInAppBundle(resolved.path(percentEncoded: false))
        }
        return dir
    }

    public static func bundledSkills(in bundled: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: bundled.path(percentEncoded: false))
            .filter { FileManager.default.fileExists(atPath: bundled.appending(path: "\($0)/SKILL.md").path(percentEncoded: false)) }
            .sorted()
    }

    /// Every agent that's set up, whether or not its links exist yet.
    public static func status(bundled: URL, home: URL, environment: [String: String]) throws -> [Link] {
        let skills = try bundledSkills(in: bundled)
        return Agent.allCases.filter { $0.isSetUp(in: home, environment: environment) }.flatMap { agent in
            skills.map { link(agent: agent, skill: $0, bundled: bundled, home: home, environment: environment) }
        }
    }

    /// Links every bundled skill for `agents` (by default, every agent that's set up), and removes this
    /// installer's links to skills the app no longer has. `force` also replaces foreign links, never folders.
    public static func install(
        bundled: URL, home: URL, environment: [String: String], agents: [Agent]? = nil, force: Bool = false
    ) throws -> [Link] {
        let fm = FileManager.default
        let agents = agents ?? Agent.allCases.filter { $0.isSetUp(in: home, environment: environment) }
        guard !agents.isEmpty else { throw SkillsError.noAgents }
        let skills = try bundledSkills(in: bundled)
        var result: [Link] = []
        for agent in agents {
            let dir = agent.skillsDirectory(in: home, environment: environment)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in try ownedLinks(in: dir) where !skills.contains(name) {
                try fm.removeItem(at: dir.appending(path: name))
            }
            for skill in skills {
                let current = link(agent: agent, skill: skill, bundled: bundled, home: home, environment: environment)
                let replace = current.state == .stale || (force && current.state == .foreign)
                if current.state == .missing || replace {
                    let path = dir.appending(path: skill)
                    if replace { try fm.removeItem(at: path) }
                    try fm.createSymbolicLink(at: path, withDestinationURL: bundled.appending(path: skill))
                    result.append(link(agent: agent, skill: skill, bundled: bundled, home: home, environment: environment))
                } else {
                    result.append(current)
                }
            }
        }
        return result
    }

    /// Removes this installer's links for every agent. Returns the paths removed.
    public static func uninstall(home: URL, environment: [String: String]) throws -> [String] {
        var removed: [String] = []
        for agent in Agent.allCases {
            let dir = agent.skillsDirectory(in: home, environment: environment)
            for name in try ownedLinks(in: dir) {
                let path = dir.appending(path: name)
                try FileManager.default.removeItem(at: path)
                removed.append(path.path(percentEncoded: false))
            }
        }
        return removed
    }

    static func link(agent: Agent, skill: String, bundled: URL, home: URL, environment: [String: String]) -> Link {
        let path = agent.skillsDirectory(in: home, environment: environment).appending(path: skill).path(percentEncoded: false)
        let fm = FileManager.default
        let destination = try? fm.destinationOfSymbolicLink(atPath: path)
        let state: Link.State
        if let destination {
            if destination == bundled.appending(path: skill).path(percentEncoded: false) {
                state = fm.fileExists(atPath: path) ? .linked : .stale
            } else {
                state = destination.contains(bundlePathComponent) ? .stale : .foreign
            }
        } else {
            state = fm.fileExists(atPath: path) ? .folder : .missing
        }
        return Link(agent: agent, skill: skill, path: path, state: state, destination: destination)
    }

    /// Names in `dir` that are links into a Captain's Log app, dangling ones included.
    static func ownedLinks(in dir: URL) throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path(percentEncoded: false)) else { return [] }
        return try fm.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).filter { name in
            let destination = try? fm.destinationOfSymbolicLink(atPath: dir.appending(path: name).path(percentEncoded: false))
            return destination?.contains(bundlePathComponent) == true
        }
    }
}
