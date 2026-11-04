import SwiftUI
import CaptainsLogKit

/// The Settings window (Cmd-,), one pane per tab.
struct SettingsView: View {
    @AppStorage(SettingsTab.storageKey) private var selection = SettingsTab.general

    var body: some View {
        TabView(selection: $selection) {
            Tab("General", systemImage: "gearshape", value: .general) { GeneralSettingsPane() }
            Tab("Sidebar", systemImage: "sidebar.left", value: .sidebar) { settingsPane { SidebarSettingsSection() } }
            Tab("Sync", systemImage: "arrow.triangle.2.circlepath", value: .sync) { SyncSettingsPane() }
            Tab("Backups", systemImage: "externaldrive", value: SettingsTab.backups) { settingsPane { BackupSettingsSection() } }
            Tab("Retention", systemImage: "clock.badge.xmark", value: SettingsTab.retention) { settingsPane { RetentionSettingsSection() } }
        }
        .frame(width: 520)
    }
}

/// Kept in UserDefaults so a link elsewhere in the app can pick the tab before calling `openSettings`.
enum SettingsTab: String {
    case general, sidebar, sync, backups, retention

    static let storageKey = "settingsTab"

    static var selected: SettingsTab {
        get { UserDefaults.standard.string(forKey: storageKey).flatMap(SettingsTab.init) ?? .general }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }
}

/// Every pane is a grouped form; the window takes the height of the tallest one shown.
private func settingsPane<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    Form { content() }
        .formStyle(.grouped)
        .frame(minHeight: 320, idealHeight: 480)
}

private struct GeneralSettingsPane: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        settingsPane {
            Section("Quick Entry") {
                Toggle("Add a to-do from any app with Control-Space", isOn: $settings.quickEntryEnabled)
                Text("If Control-Space switches your input source, macOS takes it first. Turn that off in Keyboard Shortcuts › Input Sources.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Calendar") {
                Toggle("Show weekends", isOn: $settings.showWeekends)
            }
        }
    }
}

private struct SyncSettingsPane: View {
    @Environment(AppSettings.self) private var settings

    @State private var newCalendar = ""

    var body: some View {
        @Bindable var settings = settings
        settingsPane {
            Section("GitHub") {
                Picker("Sync every", selection: $settings.githubSyncInterval) {
                    Text("1 min").tag(TimeInterval(60))
                    Text("5 min").tag(TimeInterval(300))
                    Text("15 min").tag(TimeInterval(900))
                    Text("30 min").tag(TimeInterval(1800))
                }
            }

            Section("Calendar") {
                Picker("Sync every", selection: $settings.calendarSyncInterval) {
                    Text("5 min").tag(TimeInterval(300))
                    Text("10 min").tag(TimeInterval(600))
                    Text("30 min").tag(TimeInterval(1800))
                    Text("1 hour").tag(TimeInterval(3600))
                }
                Picker("Fetch weeks ahead", selection: $settings.calendarFetchWeeks) {
                    Text("1 week").tag(1)
                    Text("2 weeks").tag(2)
                    Text("4 weeks").tag(4)
                    Text("8 weeks").tag(8)
                }
            }

            Section {
                ForEach(settings.calendarAllowlist, id: \.self) { cal in
                    RemovableRow(text: cal, monospaced: false) {
                        settings.calendarAllowlist.removeAll { $0 == cal }
                    }
                }

                HStack {
                    TextField("Calendar name", text: $newCalendar)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addCalendar)
                    Button("Add", action: addCalendar)
                        .disabled(newCalendar.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Calendar Allowlist")
            } footer: {
                Text("Only sync events from these calendars. Leave empty to sync all.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addCalendar() {
        let trimmed = newCalendar.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !settings.calendarAllowlist.contains(trimmed) else { return }
        settings.calendarAllowlist.append(trimmed)
        newCalendar = ""
    }
}

/// Orders the sidebar's tabs and leaves some out. Grouped forms ignore `onMove`, so rows move by buttons.
private struct SidebarSettingsSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let items = settings.sidebarItems
        Section {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                HStack {
                    Toggle(isOn: Binding(
                        get: { settings.isShown(item) },
                        set: { settings.setShown(item, $0) }
                    )) {
                        item.labelView
                    }
                    moveButton("chevron.up", help: "Move \(item.label) up", in: items, from: index, to: index - 1)
                    moveButton("chevron.down", help: "Move \(item.label) down", in: items, from: index, to: index + 1)
                }
            }
        } header: {
            HStack {
                Text("Tabs")
                Spacer()
                Button("Reset") {
                    settings.sidebarOrder = []
                    settings.hiddenSidebarTabs = []
                }
                .disabled(settings.sidebarOrder.isEmpty && settings.hiddenSidebarTabs.isEmpty)
            }
        }
    }

    private func moveButton(_ icon: String, help: String, in items: [SidebarItem], from index: Int, to target: Int) -> some View {
        Button {
            var reordered = items
            reordered.swapAt(index, target)
            settings.sidebarItems = reordered
        } label: {
            Image(systemName: icon)
        }
        .buttonStyle(.borderless)
        .disabled(!items.indices.contains(target))
        .help(help)
    }
}

private extension SidebarItem {
    /// Icons differ in width; a fixed frame lines the titles up.
    var labelView: some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: icon)
                .frame(width: 24)
        }
    }
}

private struct RemovableRow: View {
    let text: String
    let monospaced: Bool
    let remove: () -> Void

    var body: some View {
        HStack {
            Text(text).font(monospaced ? .body.monospaced() : .body)
            Spacer()
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Remove \(text)")
        }
        .contextMenu {
            Button("Remove", role: .destructive, action: remove)
        }
    }
}

#Preview {
    SettingsView()
        .previewEnvironment()
}
