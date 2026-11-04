import SwiftData
import SwiftUI
import CaptainsLogKit

/// One section per kind of record: a switch, how long to keep it, and how many would go now.
struct RetentionSettingsSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @State private var expired: (interviews: Int, calendarEvents: Int, pullRequests: Int)?

    var body: some View {
        @Bindable var settings = settings
        Group {
            rule(
                "Clear old interview notes",
                $settings.retention.interviews,
                count: expired?.interviews,
                noun: ("interview", "interviews"),
                detail: "Clears the notes, upsides, risk factors, conclusion, debrief notes and whiteboard link, counting from the interview or its debrief. The candidate, role, level and decision stay."
            )
            rule(
                "Delete old calendar events",
                $settings.retention.calendarEvents,
                count: expired?.calendarEvents,
                noun: ("event", "events"),
                detail: "Only events without meeting notes or an interview."
            )
            rule(
                "Delete old pull requests",
                $settings.retention.pullRequests,
                count: expired?.pullRequests,
                noun: ("pull request", "pull requests"),
                detail: "Counted from the PR's last update on GitHub, and older ones stop syncing. Linked PRs go too; their todos stay."
            )
            Section {
                Text("Removal is permanent and runs every hour. Backups keep removed data until they're pruned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: settings.retention) { refresh() }
    }

    private func rule(
        _ title: String,
        _ rule: Binding<RetentionRule>,
        count: Int?,
        noun: (one: String, many: String),
        detail: String
    ) -> some View {
        Section {
            Toggle(title, isOn: rule.isEnabled)
            Picker("After", selection: rule.days) {
                ForEach(RetentionRule.dayChoices, id: \.self) { Text("\($0) days").tag($0) }
            }
            .disabled(!rule.wrappedValue.isEnabled)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(detail)
                if rule.wrappedValue.isEnabled, let count {
                    Text(count == 0 ? "Nothing to remove now." : "\(count) \(count == 1 ? noun.one : noun.many) to remove at the next run.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// What the next run would remove, with every rule counted as if on so the number is ready when one is switched on.
    private func refresh() {
        var all = settings.retention
        all.interviews.isEnabled = true
        all.calendarEvents.isEnabled = true
        all.pullRequests.isEnabled = true
        guard let found = try? ExpiredRecords.find(all, in: context) else { return }
        expired = (found.interviews.count, found.calendarEvents.count, found.pullRequests.count)
    }
}
