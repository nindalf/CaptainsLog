import Foundation

/// Project names are unique (`#Unique` on `Project.name`), and a clash silently upserts over the
/// existing project. Every create and rename goes through these checks.
public enum ProjectNaming {
    /// `base`, or `base 2`, `base 3`... whichever is first unused, compared case-insensitively.
    public static func uniqueName(base: String = "New Project", existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        if !taken.contains(base.lowercased()) { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    /// The trimmed name if `project` may take it: non-empty and not used by another project.
    public static func validated(_ name: String, for project: Project, among projects: [Project]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clash = projects.contains {
            $0.id != project.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        return clash ? nil : trimmed
    }
}
