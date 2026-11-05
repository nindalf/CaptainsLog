import SwiftUI
import CaptainsLogKit

struct CalendarEventPopover: View {
    let event: CalendarEvent
    let onAction: (CalendarEventAction) -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

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
                if let url = event.meetingURL {
                    Button {
                        openURL(url)
                        dismiss()
                    } label: {
                        Label("Join", systemImage: "video")
                    }
                    .buttonStyle(.borderedProminent)
                    .help(url.absoluteString)
                }

                Button { onAction(.createMeeting) } label: {
                    Label("Add Notes", systemImage: "square.and.pencil")
                }

                Spacer()

                // Rare next to joining or taking notes, so icons only; the context menu has them too.
                Group {
                    Button { onAction(.hide) } label: {
                        Label("Hide Event", systemImage: "eye.slash")
                    }
                    .help("Hide Event")

                    Button(role: .destructive) { onAction(.delete) } label: {
                        Label("Delete Event", systemImage: "trash")
                    }
                    .help("Delete Event")
                }
                .labelStyle(.iconOnly)
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
