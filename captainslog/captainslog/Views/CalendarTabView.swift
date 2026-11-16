import SwiftUI
import SwiftData
import CaptainsLogKit

struct CalendarTabView: View {
    @Query(Self.firstEvent) private var anyEvent: [CalendarEvent]

    private static var firstEvent: FetchDescriptor<CalendarEvent> {
        var descriptor = FetchDescriptor<CalendarEvent>()
        descriptor.fetchLimit = 1
        return descriptor
    }

    @Environment(SyncCoordinator.self) private var syncCoordinator

    var body: some View {
        VStack(spacing: 0) {
            banner
            CalendarWeekView()
                .overlay { emptyOverlay }
        }
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem {
                Button { syncCoordinator.syncCalendarNow() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh calendar")
                .disabled(syncCoordinator.isSyncing)
            }
        }
    }

    private var setup: SetupInstruction? { SetupInstruction.calendar(syncCoordinator.calendarSetup, canLogIn: syncCoordinator.canLogInToCalendar) }

    /// A setup step or a failing sync, over a calendar that still shows what synced before.
    @ViewBuilder
    private var banner: some View {
        if let setup, !anyEvent.isEmpty {
            SetupInstructionView(instruction: setup, style: .banner)
                .padding(12)
        } else if syncCoordinator.history.sources[.calendar]?.isFailing == true {
            SyncStatusLabel(source: .calendar)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    /// Over an empty week grid: the setup step, or that the first sync is under way.
    @ViewBuilder
    private var emptyOverlay: some View {
        if anyEvent.isEmpty {
            Group {
                if let setup {
                    SetupInstructionView(instruction: setup)
                } else if syncCoordinator.calendarSetup == .ready,
                    syncCoordinator.history.sources[.calendar]?.lastSuccess == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Syncing your calendar").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .opacity(setup == nil && syncCoordinator.calendarSetup != .ready ? 0 : 1)
        }
    }
}

#Preview {
    NavigationStack {
        CalendarTabView()
    }
    .previewEnvironment()
}
