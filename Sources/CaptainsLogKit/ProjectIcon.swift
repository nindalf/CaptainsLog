import Foundation

/// The SF Symbols a project can use. A folder by default: circles read as checkboxes.
public enum ProjectIcon {
    public static let defaultName = "folder"

    public static let choices = [
        "folder", "briefcase", "doc.text", "book", "chart.bar", "target",
        "flag", "lightbulb", "hammer", "wrench.and.screwdriver", "gearshape", "shield",
        "lock", "magnifyingglass", "person.2", "bubble.left.and.bubble.right", "calendar", "airplane",
        "graduationcap", "building.2", "cart", "leaf", "heart", "star",
    ]
}

extension Project {
    public var icon: String { iconName ?? ProjectIcon.defaultName }

    /// Sets one of `ProjectIcon.choices`. The default is stored as nil, which marks a project
    /// nobody has picked an icon for.
    public func setIcon(_ name: String) {
        iconName = name == ProjectIcon.defaultName ? nil : name
    }
}
