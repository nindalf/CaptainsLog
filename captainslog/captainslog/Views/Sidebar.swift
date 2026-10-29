import SwiftUI
import CaptainsLogKit

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard
    case log
    case meetings
    case pullRequests
    case todos
    case interviews
    case people
    case search

    var id: SidebarItem { self }

    var label: String {
        switch self {
        case .dashboard: "Dashboard"
        case .log: "Log"
        case .meetings: "Calendar"
        case .pullRequests: "Pull Requests"
        case .todos: "Todos"
        case .interviews: "Interviews"
        case .people: "People"
        case .search: "Search"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "house"
        case .log: "book"
        case .meetings: "calendar"
        case .pullRequests: "arrow.triangle.pull"
        case .todos: "checklist"
        case .interviews: "person.badge.clock"
        case .people: "person.2"
        case .search: "magnifyingglass"
        }
    }
}

extension AppSettings {
    /// Every tab in the order Settings puts them, hidden ones included.
    var sidebarItems: [SidebarItem] {
        get {
            let ordered = sidebarOrder.compactMap(SidebarItem.init(rawValue:))
            return ordered + SidebarItem.allCases.filter { !ordered.contains($0) }
        }
        set { sidebarOrder = newValue.map(\.rawValue) }
    }

    var visibleSidebarItems: [SidebarItem] {
        sidebarItems.filter(isShown)
    }

    func isShown(_ item: SidebarItem) -> Bool {
        !hiddenSidebarTabs.contains(item.rawValue)
    }

    func setShown(_ item: SidebarItem, _ shown: Bool) {
        let others = hiddenSidebarTabs.filter { $0 != item.rawValue }
        hiddenSidebarTabs = shown ? others : others + [item.rawValue]
    }
}

struct Sidebar: View {
    @Environment(AppSettings.self) private var settings
    @Binding var selection: SidebarItem?

    var body: some View {
        List(settings.visibleSidebarItems, selection: $selection) { item in
            Label(item.label, systemImage: item.icon)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }
}
