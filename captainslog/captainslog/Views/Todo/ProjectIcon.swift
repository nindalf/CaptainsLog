import SwiftUI
import CaptainsLogKit

/// The SF Symbols a project can use. A folder by default: circles read as checkboxes.
enum ProjectIcon {
    static let defaultName = "folder"

    static let choices = [
        "folder", "briefcase", "doc.text", "book", "chart.bar", "target",
        "flag", "lightbulb", "hammer", "wrench.and.screwdriver", "gearshape", "shield",
        "lock", "magnifyingglass", "person.2", "bubble.left.and.bubble.right", "calendar", "airplane",
        "graduationcap", "building.2", "cart", "leaf", "heart", "star",
    ]
}

extension Project {
    var icon: String { iconName ?? ProjectIcon.defaultName }

    /// What a delete would unlink, for the confirmation. Everything is kept: the relationships nullify.
    var deletionSummary: String {
        let linked: [(Int, String, String)] = [
            (todos?.count ?? 0, "to-do", "to-dos"),
            (logEntries?.count ?? 0, "log entry", "log entries"),
            (meetings?.count ?? 0, "meeting", "meetings"),
            (pullRequests?.count ?? 0, "pull request", "pull requests"),
        ]
        let parts = linked.filter { $0.0 > 0 }.map { "\($0.0) \($0.0 == 1 ? $0.1 : $0.2)" }
        guard !parts.isEmpty else { return "The project has nothing linked to it." }
        return "\(parts.joined(separator: ", ")) will be kept, without a project."
    }
}

/// A grid of `ProjectIcon.choices`; picking one sets the project's icon.
struct ProjectIconPicker: View {
    @Bindable var project: Project
    var onPick: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 6), spacing: 4) {
            ForEach(ProjectIcon.choices, id: \.self) { name in
                Button {
                    project.iconName = name == ProjectIcon.defaultName ? nil : name
                    onPick()
                    dismiss()
                } label: {
                    Image(systemName: name)
                        .frame(width: 30, height: 28)
                        .foregroundStyle(project.icon == name ? Color.white : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(project.icon == name ? Color.accentColor : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(name)
            }
        }
        .padding(10)
    }
}
