import Foundation

public enum GitHubRepo {
    /// "org/repo" from what someone types or pastes: the name itself, a github.com URL (a PR or file
    /// link included) or an SSH remote. Nil when it isn't one.
    public static func parse(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var isLink = false
        for prefix in ["git@github.com:", "https://", "http://", "www.", "github.com/"]
        where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            isLink = true
        }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        // A link can go on past org/repo, to a PR or a file; a bare name can't.
        guard parts.count == 2 || (isLink && parts.count > 2) else { return nil }
        let org = String(parts[0])
        var repo = String(parts[1])
        if repo.lowercased().hasSuffix(".git") { repo.removeLast(4) }
        guard isName(org), isName(repo) else { return nil }
        return "\(org)/\(repo)"
    }

    private static func isName(_ part: String) -> Bool {
        !part.isEmpty && part != "." && part != ".."
            && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }
}
