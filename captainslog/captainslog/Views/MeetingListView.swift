import SwiftUI
import SwiftData
import CaptainsLogKit

private enum MeetingViewMode: String, CaseIterable {
    case calendar = "Calendar"
    case list = "List"
}

struct MeetingListView: View {
    @Query(sort: \Meeting.date, order: .reverse)
    private var meetings: [Meeting]

    @Query(Self.firstEvent) private var anyEvent: [CalendarEvent]

    private static var firstEvent: FetchDescriptor<CalendarEvent> {
        var descriptor = FetchDescriptor<CalendarEvent>()
        descriptor.fetchLimit = 1
        return descriptor
    }

    @Environment(SyncCoordinator.self) private var syncCoordinator

    @AppStorage("meetingViewMode") private var viewMode = MeetingViewMode.calendar

    var body: some View {
        VStack(spacing: 0) {
            banner
            switch viewMode {
            case .calendar:
                CalendarWeekView()
                    .overlay { emptyOverlay }
            case .list:
                if meetings.isEmpty {
                    if anyEvent.isEmpty, let setup {
                        SetupInstructionView(instruction: setup)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                    } else {
                        ContentUnavailableView(
                            "No Meetings", systemImage: "person.2",
                            description: Text("Click an event in the calendar, then Add Notes."))
                    }
                } else {
                    meetingList
                }
            }
        }
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $viewMode) {
                    ForEach(MeetingViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            ToolbarItem {
                Button { syncCoordinator.syncCalendarNow() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh calendar")
                .disabled(syncCoordinator.isSyncing)
            }
        }
    }

    private var setup: SetupInstruction? { SetupInstruction.calendar(syncCoordinator.calendarSetup) }

    /// A setup step or a failing sync, over a calendar that still shows what synced before.
    @ViewBuilder
    private var banner: some View {
        if let setup, !anyEvent.isEmpty {
            SetupInstructionView(instruction: setup, centered: false)
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

    private var meetingList: some View {
        List {
            ForEach(meetings) { meeting in
                NavigationLink(value: meeting) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.title).font(.headline)
                        HStack {
                            Text(DateLabel.dayTime(meeting.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !meeting.attendees.isEmpty {
                                Text("^[\(meeting.attendees.count) attendee](inflect: true)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        MeetingListView()
    }
    .previewEnvironment()
}
