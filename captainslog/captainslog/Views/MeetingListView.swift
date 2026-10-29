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

    @Environment(SyncCoordinator.self) private var syncCoordinator

    @AppStorage("meetingViewMode") private var viewMode = MeetingViewMode.calendar

    var body: some View {
        Group {
            switch viewMode {
            case .calendar:
                CalendarWeekView()
            case .list:
                meetingList
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
