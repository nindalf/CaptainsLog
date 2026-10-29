import SwiftUI
import CaptainsLogKit

enum TimeGridConstants {
    static let hourHeight: CGFloat = 60
    static let gutterWidth: CGFloat = 50
    static let startHour: Int = 8
    static let endHour: Int = 19
    static let totalHours: Int = endHour - startHour
    static let gridHeight: CGFloat = CGFloat(totalHours) * hourHeight
}

struct TimeGridView: View {
    let events: [CalendarEvent]
    let weekStart: Date
    let dayCount: Int
    /// Override to compress the day into a fixed height (the dashboard's single-day grid).
    var hourHeight: CGFloat = TimeGridConstants.hourHeight
    let onTap: (CalendarEvent) -> Void

    private let calendar = Calendar.current

    private var gridHeight: CGFloat {
        CGFloat(TimeGridConstants.totalHours) * hourHeight
    }

    var body: some View {
        GeometryReader { geo in
            let dayWidth = (geo.size.width - TimeGridConstants.gutterWidth) / CGFloat(dayCount)

            ZStack(alignment: .topLeading) {
                gridLines(dayWidth: dayWidth)
                eventBlocks(dayWidth: dayWidth)
                TimelineView(.everyMinute) { context in
                    currentTimeIndicator(dayWidth: dayWidth, now: context.date)
                }
            }
        }
        .frame(height: gridHeight)
    }

    // MARK: - Grid lines

    private func gridLines(dayWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...TimeGridConstants.totalHours, id: \.self) { hourOffset in
                let y = CGFloat(hourOffset) * hourHeight

                // Hour label
                Text(hourLabel(TimeGridConstants.startHour + hourOffset))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: TimeGridConstants.gutterWidth - 8, alignment: .trailing)
                    .position(
                        x: (TimeGridConstants.gutterWidth - 8) / 2,
                        y: y
                    )

                // Horizontal line
                Path { path in
                    path.move(to: CGPoint(x: TimeGridConstants.gutterWidth, y: y))
                    path.addLine(to: CGPoint(
                        x: TimeGridConstants.gutterWidth + CGFloat(dayCount) * dayWidth,
                        y: y
                    ))
                }
                .stroke(.quaternary, lineWidth: 0.5)
            }

            // Vertical day separators
            ForEach(0...dayCount, id: \.self) { dayIndex in
                let x = TimeGridConstants.gutterWidth + CGFloat(dayIndex) * dayWidth
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: gridHeight))
                }
                .stroke(.quaternary, lineWidth: 0.5)
            }
        }
    }

    // MARK: - Event blocks

    private func eventBlocks(dayWidth: CGFloat) -> some View {
        ForEach(layoutAllEvents(dayWidth: dayWidth), id: \.event.id) { item in
            CalendarEventBlock(
                event: item.event,
                frame: item.frame,
                onTap: { onTap(item.event) }
            )
        }
    }

    // MARK: - Current time indicator

    @ViewBuilder
    private func currentTimeIndicator(dayWidth: CGFloat, now: Date) -> some View {
        ZStack(alignment: .topLeading) {
            let todayOffset = dayOffsetForDate(now)
            if let todayOffset, todayOffset < dayCount {
                let components = calendar.dateComponents([.hour, .minute], from: now)
                let hour = components.hour ?? 0
                let minute = components.minute ?? 0
                let fractionalHour = Double(hour) + Double(minute) / 60.0
                let y = CGFloat(fractionalHour - Double(TimeGridConstants.startHour)) * hourHeight

                if y >= 0 && y <= gridHeight {
                    let x = TimeGridConstants.gutterWidth + CGFloat(todayOffset) * dayWidth

                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)

                    Path { path in
                        path.move(to: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: x + dayWidth, y: y))
                    }
                    .stroke(.red, lineWidth: 1.5)
                }
            }
        }
    }

    // MARK: - Layout algorithm

    private struct LayoutItem {
        let event: CalendarEvent
        let frame: CGRect
    }

    private func layoutAllEvents(dayWidth: CGFloat) -> [LayoutItem] {
        var items: [LayoutItem] = []

        for dayOffset in 0..<dayCount {
            let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
            let dayEvents = events.filter {
                !$0.isAllDay && calendar.isDate($0.startTime, inSameDayAs: dayDate)
            }

            let columnX = TimeGridConstants.gutterWidth + CGFloat(dayOffset) * dayWidth
            let laid = layoutDayEvents(dayEvents, columnX: columnX, dayWidth: dayWidth)
            items.append(contentsOf: laid)
        }

        return items
    }

    private func layoutDayEvents(
        _ events: [CalendarEvent],
        columnX: CGFloat,
        dayWidth: CGFloat
    ) -> [LayoutItem] {
        guard !events.isEmpty else { return [] }

        let sorted = events.sorted { a, b in
            if a.startTime != b.startTime { return a.startTime < b.startTime }
            return a.endTime > b.endTime
        }

        let groups = groupOverlapping(sorted)
        var items: [LayoutItem] = []

        for group in groups {
            let slotCount = group.count
            let slotWidth = (dayWidth - 2) / CGFloat(slotCount)

            for (slotIndex, event) in group.enumerated() {
                let y = yPosition(for: event.startTime)
                let height = max(
                    hourHeight / 4,
                    yPosition(for: event.endTime) - y
                )
                let x = columnX + 1 + CGFloat(slotIndex) * slotWidth

                items.append(LayoutItem(
                    event: event,
                    frame: CGRect(x: x, y: y, width: slotWidth, height: height)
                ))
            }
        }

        return items
    }

    private func groupOverlapping(_ events: [CalendarEvent]) -> [[CalendarEvent]] {
        var groups: [[CalendarEvent]] = []
        var currentGroup: [CalendarEvent] = []
        var groupEnd: Date = .distantPast

        for event in events {
            if event.startTime >= groupEnd {
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                }
                currentGroup = [event]
                groupEnd = event.endTime
            } else {
                currentGroup.append(event)
                if event.endTime > groupEnd {
                    groupEnd = event.endTime
                }
            }
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        return groups
    }

    private func yPosition(for date: Date) -> CGFloat {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let fractional = Double(hour) + Double(minute) / 60.0
        return CGFloat(fractional - Double(TimeGridConstants.startHour)) * hourHeight
    }

    private func dayOffsetForDate(_ date: Date) -> Int? {
        for offset in 0..<dayCount {
            let dayDate = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            if calendar.isDate(dayDate, inSameDayAs: date) {
                return offset
            }
        }
        return nil
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0 { return "12 AM" }
        if h < 12 { return "\(h) AM" }
        if h == 12 { return "12 PM" }
        return "\(h - 12) PM"
    }
}
