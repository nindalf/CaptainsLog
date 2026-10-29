import SwiftUI
import CaptainsLogKit

/// The Dashboard's schedule as a list: today's events, or the next day with any when today has none.
struct DashboardAgenda: View {
    let events: [CalendarEvent]
    let onTap: (CalendarEvent) -> Void

    var body: some View {
        // Redrawn each minute so the current event and past ones stay marked.
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let allDay = allDayEvents(now: now)
        VStack(alignment: .leading, spacing: 2) {
            if !allDay.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(allDay) { event in
                        Button { onTap(event) } label: {
                            Text(event.title)
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Self.color(event).opacity(0.15), in: .rect(cornerRadius: 4))
                                .foregroundStyle(Self.color(event))
                        }
                        .buttonStyle(.plain)
                        .calendarEventContextMenu(event)
                    }
                }
                .padding(.bottom, 4)
            }
            if let day = Agenda.day(among: events, now: now) {
                if !day.isToday {
                    Text("Nothing today. \(day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))):")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
                ForEach(day.events) { event in
                    row(event, now: now)
                }
            } else {
                Text("Nothing in the next two weeks")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func row(_ event: CalendarEvent, now: Date) -> some View {
        let isPast = event.endTime <= now
        let isNow = event.startTime <= now && now < event.endTime
        return Button { onTap(event) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(event.startTime.formatted(.dateTime.hour().minute()))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Self.color(event))
                    .frame(width: 3, height: 14)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .fontWeight(isNow ? .semibold : .regular)
                        .lineLimit(1)
                    if let detail = detail(event) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isNow {
                    Text("Now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Self.color(event))
                }
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
            .opacity(isPast ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .calendarEventContextMenu(event)
    }

    /// Length, and who else is there for a small meeting.
    private func detail(_ event: CalendarEvent) -> String? {
        let minutes = Int(event.endTime.timeIntervalSince(event.startTime) / 60)
        let length = minutes < 60 || minutes % 60 != 0 ? "\(minutes) min" : "\(minutes / 60) h"
        let people = event.attendees.map(\.name).sorted()
        guard !people.isEmpty else { return length }
        let names = people.count <= 3 ? people.joined(separator: ", ") : "\(people.count) people"
        return "\(length) · \(names)"
    }

    private func allDayEvents(now: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { $0.isAllDay && !$0.isHidden && $0.startTime < end && $0.endTime > start }
    }

    static func color(_ event: CalendarEvent) -> Color {
        if event.meeting != nil { return .blue }
        if event.interview != nil { return .green }
        return .gray
    }
}
