import SwiftUI
import SwiftData
import CaptainsLogKit

struct MenuBarView: View {
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<CalendarEvent> { !$0.isHidden }, sort: \CalendarEvent.startTime)
    private var allEvents: [CalendarEvent]

    private var upcomingEvents: [CalendarEvent] {
        let now = Date.now
        return allEvents.filter { $0.startTime > now }
    }

    @Query(filter: #Predicate<PullRequest> { $0.isAuthoredByMe && $0.stateRawValue == "open" })
    private var myOpenPRs: [PullRequest]

    @Query(filter: #Predicate<PullRequest> {
        !$0.isAuthoredByMe && !$0.isTeammateOnly && $0.stateRawValue == "open"
    })
    private var openReviewRequests: [PullRequest]

    private var reviewRequests: [PullRequest] {
        openReviewRequests.filter { !settings.isHidden($0) }
    }

    @Query(filter: #Predicate<Todo> { $0.completedDate == nil })
    private var activeTodos: [Todo]

    private var todayTodos: [Todo] {
        let now = Date.now
        return activeTodos.filter { SmartList.today.contains($0, now: now) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let next = upcomingEvents.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next").font(.caption).foregroundStyle(.secondary)
                    Text(next.title).font(.headline)
                    Text(DateLabel.dayTime(next.startTime))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No upcoming events")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 16) {
                StatPill(label: "My PRs", count: myOpenPRs.count, color: .blue)
                StatPill(label: "Reviews", count: reviewRequests.count, color: .orange)
                StatPill(label: "Today", count: todayTodos.count, color: todayTodos.isEmpty ? .secondary : .yellow)
            }

            Divider()

            HStack {
                if sync.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Syncing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = sync.lastError ?? sync.backupError {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if let gh = sync.lastGitHubSync {
                    Text("Last sync: \(gh, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Sync") {
                    sync.syncNow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(sync.isSyncing)
            }

        }
        .padding()
        .frame(width: 300)
    }
}

private struct StatPill: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    MenuBarView()
        .previewEnvironment()
}
