import SwiftData
import SwiftUI
import CaptainsLogKit

/// One section per kind of record: a switch, how long to keep it, and how many would go now.
struct RetentionSettingsSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @State private var expired: ExpiredCounts?

    private struct ExpiredCounts {
        var interviews: Int
        var meetings: Int
        var calendarEvents: Int
        var pullRequests: Int
    }

    var body: some View {
        @Bindable var settings = settings
        Group {
            rule(
                "Delete old interviews",
                $settings.retention.interviews,
                toRemove: expired.map { [count($0.interviews, "interview", "interviews")] },
                detail: "Counting from the interview or its debrief. Its calendar event and todos go too. An interview with an open todo, such as an unsubmitted scorecard, stays until the todo is done."
            )
            rule(
                "Delete old meetings and calendar events",
                $settings.retention.calendarEvents,
                toRemove: expired.map {
                    [count($0.meetings, "meeting", "meetings"), count($0.calendarEvents, "event", "events")]
                },
                detail: "Meeting notes, prep, transcripts and summaries go too; their todos stay. Interview events go with their interview."
            )
            rule(
                "Delete old pull requests",
                $settings.retention.pullRequests,
                toRemove: expired.map { [count($0.pullRequests, "pull request", "pull requests")] },
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
        toRemove: [String?]?,
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
                if rule.wrappedValue.isEnabled, let toRemove {
                    let parts = toRemove.compactMap { $0 }
                    Text(parts.isEmpty ? "Nothing to remove now." : "\(parts.joined(separator: " and ")) to remove at the next run.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Nil for none, so a rule with nothing to remove says so once.
    private func count(_ n: Int, _ one: String, _ many: String) -> String? {
        n == 0 ? nil : "\(n) \(n == 1 ? one : many)"
    }

    /// What the next run would remove, with every rule counted as if on so the number is ready when one is switched on.
    private func refresh() {
        var all = settings.retention
        all.interviews.isEnabled = true
        all.calendarEvents.isEnabled = true
        all.pullRequests.isEnabled = true
        guard let found = try? ExpiredRecords.find(all, in: context) else { return }
        expired = ExpiredCounts(
            interviews: found.interviews.count,
            meetings: found.meetings.count,
            calendarEvents: found.calendarEvents.count,
            pullRequests: found.pullRequests.count
        )
    }
}
