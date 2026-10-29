import SwiftUI
import CaptainsLogKit

struct CalendarEventBlock: View {
    let event: CalendarEvent
    let frame: CGRect
    let onTap: () -> Void

    private var isPast: Bool {
        event.endTime < .now
    }

    var body: some View {
        Button { onTap() } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accentColor)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.caption2.bold())
                        .lineLimit(frame.height > 40 ? 2 : 1)

                    if frame.height > 30 {
                        Text(timeRange)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 4)
                .padding(.trailing, 2)

                Spacer(minLength: 0)
            }
            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            .padding(.vertical, 2)
            .background(accentColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .opacity(isPast ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .calendarEventContextMenu(event)
        .position(x: frame.midX, y: frame.midY)
    }

    private var accentColor: Color {
        if event.meeting != nil { return .blue }
        if event.interview != nil { return .green }
        return .gray
    }

    private var timeRange: String {
        let start = event.startTime.formatted(.dateTime.hour().minute())
        let end = event.endTime.formatted(.dateTime.hour().minute())
        return "\(start) - \(end)"
    }
}
