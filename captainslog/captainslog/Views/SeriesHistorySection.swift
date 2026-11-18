import SwiftUI
import SwiftData
import CaptainsLogKit

/// The earlier meetings of a recurring series, collapsed under a heading until opened. Those with
/// notes open their meeting; calendar events without one show as such, with Add Notes.
struct SeriesHistorySection: View {
    let meeting: Meeting
    @Query private var candidates: [CalendarEvent]
    @State private var isExpanded = false
    @Environment(Navigator.self) private var navigator
    @Environment(\.modelContext) private var modelContext

    private static let rowLimit = 10

    init(meeting: Meeting) {
        self.meeting = meeting
        // A one-off meeting's start of distantPast matches nothing.
        let prefix = (meeting.calendarEvent?.seriesID ?? "") + "_"
        let start = meeting.calendarEvent?.seriesID == nil ? Date.distantPast : meeting.date
        _candidates = Query(filter: #Predicate<CalendarEvent> {
            $0.startTime < start && $0.externalID.starts(with: prefix)
        })
    }

    private var events: [CalendarEvent] {
        meeting.earlierSeriesEvents(among: candidates)
    }

    var body: some View {
        let events = events
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button { isExpanded.toggle() } label: {
                    SectionHeader(title: "Previous Meetings", count: events.count, isExpanded: isExpanded)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        DetailRows(data: events, limit: Self.rowLimit) { event in
                            if let previous = event.meeting {
                                NavigationLink(value: previous) { meetingRow(previous) }
                                    .buttonStyle(.plain)
                            } else {
                                eventRow(event)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quinary, in: .rect(cornerRadius: 10))
                }
            }
        }
    }

    private func meetingRow(_ previous: Meeting) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(DateLabel.day(previous.date))
                .frame(width: 90, alignment: .leading)
            Text(preview(previous))
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Text(DateLabel.day(event.startTime))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text("No notes")
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Add Notes", systemImage: "square.and.pencil") {
                event.createMeeting(in: modelContext)
                try? modelContext.save()
                navigator.openEvent(event)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// The first line written, summary first, without its markdown markers.
    private func preview(_ previous: Meeting) -> String {
        for text in [previous.summary, previous.notes, previous.prepNotes] {
            let line = (text ?? "").split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#-*>[] ").union(.whitespaces)) }
                .first { !$0.isEmpty }
            if let line { return line }
        }
        return "Notes"
    }
}
