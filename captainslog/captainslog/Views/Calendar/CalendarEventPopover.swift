import SwiftUI
import CaptainsLogKit

struct CalendarEventPopover: View {
    let event: CalendarEvent
    let onAction: (CalendarEventAction) -> Void

    enum CalendarEventAction {
        case createMeeting
        case hide
        case delete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(event.title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Label(timeRange, systemImage: "clock")
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "location")
                }
                if !event.attendees.isEmpty {
                    Label(
                        event.attendees.map(\.name).joined(separator: ", "),
                        systemImage: "person.2"
                    )
                    .lineLimit(2)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            HStack {
                Button { onAction(.createMeeting) } label: {
                    Label("Add Notes", systemImage: "square.and.pencil")
                }

                Button { onAction(.hide) } label: {
                    Label("Hide Event", systemImage: "eye.slash")
                }

                Button(role: .destructive) { onAction(.delete) } label: {
                    Label("Delete Event", systemImage: "trash")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .frame(minWidth: 250)
    }

    private var timeRange: String {
        if event.isAllDay { return "All day" }
        let start = event.startTime.formatted(.dateTime.hour().minute())
        let end = event.endTime.formatted(.dateTime.hour().minute())
        let day = event.startTime.formatted(.dateTime.weekday(.wide).month().day())
        return "\(day), \(start) - \(end)"
    }
}
