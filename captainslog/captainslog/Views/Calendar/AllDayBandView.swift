import SwiftUI
import CaptainsLogKit

struct AllDayBandView: View {
    let events: [CalendarEvent]
    let weekStart: Date
    let dayCount: Int
    let onTap: (CalendarEvent) -> Void

    private let calendar = Calendar.current

    var body: some View {
        if events.isEmpty { return AnyView(EmptyView()) }

        return AnyView(
            HStack(alignment: .top, spacing: 0) {
                Color.clear
                    .frame(width: TimeGridConstants.gutterWidth)

                ForEach(0..<dayCount, id: \.self) { offset in
                    let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
                    let dayEvents = events.filter {
                        $0.startTime < calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
                        && $0.endTime > calendar.startOfDay(for: date)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(dayEvents) { event in
                            Button { onTap(event) } label: {
                                Text(event.title)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(eventColor(event).opacity(0.15))
                                    .foregroundStyle(eventColor(event))
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                            }
                            .buttonStyle(.plain)
                            .calendarEventContextMenu(event)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 1)
                }
            }
            .padding(.vertical, 2)
            .background(.bar)
            .fixedSize(horizontal: false, vertical: true)
        )
    }

    private func eventColor(_ event: CalendarEvent) -> Color {
        if event.meeting != nil { return .blue }
        if event.interview != nil { return .green }
        return .secondary
    }
}
