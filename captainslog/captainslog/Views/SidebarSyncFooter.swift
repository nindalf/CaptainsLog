import SwiftUI
import CaptainsLogKit

/// The one place sync shows: when GitHub and the calendar last synced, or that one failed, and
/// Sync Now. A click on the status shows each source's, with a failure's error.
struct SidebarSyncFooter: View {
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AppSettings.self) private var settings
    @State private var showsDetails = false

    /// Sources whose tab is shown and that have synced or failed at least once.
    private var sources: [SyncSource] {
        var sources: [SyncSource] = []
        if settings.isShown(.pullRequests) { sources.append(.github) }
        if settings.isShown(.meetings) { sources.append(.calendar) }
        return sources.filter { sync.history.sources[$0] != nil }
    }

    var body: some View {
        HStack(spacing: 6) {
            Button { showsDetails.toggle() } label: {
                status.frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(sources.isEmpty)
            .popover(isPresented: $showsDetails, arrowEdge: .top) { details }
            Button { sync.syncNow() } label: {
                Label("Sync Now", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(sync.isSyncing)
            .help(AppCommand.sync.help("Sync Now"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var status: some View {
        let failing = sources.filter { sync.history.sources[$0]?.isFailing == true }
        if sync.isSyncing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Syncing")
            }
        } else if !failing.isEmpty {
            Label(
                failing.count == 1 ? "\(failing[0].displayName) sync failed" : "Sync failed",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.red)
        } else if let oldest = sources.compactMap({ sync.history.sources[$0]?.lastSuccess }).min() {
            // The oldest, so "synced 2 minutes ago" is true of everything.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text("Synced \(Self.relative.localizedString(for: min(oldest, context.date), relativeTo: context.date))")
            }
            .help(sources.map { "\($0.displayName): \(sync.history.sources[$0]?.lastSuccess?.formatted(date: .omitted, time: .shortened) ?? "never")" }
                .joined(separator: "\n"))
        } else {
            Text("Not synced yet")
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter
    }()

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sources, id: \.self) { source in
                SyncStatusLabel(source: source)
            }
        }
        .frame(width: 280, alignment: .leading)
        .padding(12)
    }
}
