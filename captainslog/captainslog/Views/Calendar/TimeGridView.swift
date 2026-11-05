import SwiftUI
import CaptainsLogKit

enum TimeGridConstants {
    static let hourHeight: CGFloat = 60
    static let gutterWidth: CGFloat = 50
    static let startHour: Int = 0
    static let endHour: Int = 24
    /// The calendar opens scrolled to here: the working day.
    static let workdayStartHour: Int = 8
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

                // Hour label, skipped at the grid's edges where it would be cut in half
                if hourOffset > 0 && hourOffset < TimeGridConstants.totalHours {
                    Text(hourLabel(TimeGridConstants.startHour + hourOffset))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: TimeGridConstants.gutterWidth - 8, alignment: .trailing)
                        .position(
                            x: (TimeGridConstants.gutterWidth - 8) / 2,
                            y: y
                        )
                }

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

        let slots = EventColumns.layout(events.map { ($0.startTime, $0.endTime) })
        let laneWidth = dayWidth - 2

        return zip(events, slots).map { event, slot in
            let y = yPosition(for: event.startTime)
            let height = max(hourHeight / 4, endYPosition(for: event) - y)
            let columnWidth = laneWidth / CGFloat(slot.columns)
            let x = columnX + 1 + CGFloat(slot.column) * columnWidth
            return LayoutItem(
                event: event,
                frame: CGRect(x: x, y: y, width: columnWidth * CGFloat(slot.span), height: height)
            )
        }
    }

    private func yPosition(for date: Date) -> CGFloat {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let fractional = Double(hour) + Double(minute) / 60.0
        return CGFloat(fractional - Double(TimeGridConstants.startHour)) * hourHeight
    }

    /// An event that runs past midnight ends at the bottom of its start day's column.
    private func endYPosition(for event: CalendarEvent) -> CGFloat {
        guard calendar.isDate(event.endTime, inSameDayAs: event.startTime) else { return gridHeight }
        return yPosition(for: event.endTime)
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

/// Places a day's events side by side the way Google Calendar does: each event takes the
/// first column free at its start, so a cluster is only as wide as its peak overlap, then
/// stretches right across columns that stay free for its whole span.
enum EventColumns {
    struct Slot: Equatable {
        let column: Int
        let span: Int
        let columns: Int
    }

    /// Events shorter than this still draw this tall, so they lay out as if they last it.
    static let minimumDuration: TimeInterval = 15 * 60

    static func layout(_ intervals: [(start: Date, end: Date)]) -> [Slot] {
        let spans = intervals.map { ($0.start, max($0.end, $0.start + minimumDuration)) }
        let order = spans.indices.sorted { a, b in
            if spans[a].0 != spans[b].0 { return spans[a].0 < spans[b].0 }
            return spans[a].1 > spans[b].1
        }
        func overlaps(_ a: Int, _ b: Int) -> Bool {
            spans[a].0 < spans[b].1 && spans[b].0 < spans[a].1
        }

        var slots = [Slot?](repeating: nil, count: spans.count)
        var columns: [[Int]] = []
        var clusterEnd = Date.distantPast

        func closeCluster() {
            for (column, members) in columns.enumerated() {
                for event in members {
                    var span = 1
                    while column + span < columns.count,
                          !columns[column + span].contains(where: { overlaps($0, event) }) {
                        span += 1
                    }
                    slots[event] = Slot(column: column, span: span, columns: columns.count)
                }
            }
            columns = []
        }

        for event in order {
            if spans[event].0 >= clusterEnd { closeCluster() }
            if let free = columns.firstIndex(where: { spans[$0.last!].1 <= spans[event].0 }) {
                columns[free].append(event)
            } else {
                columns.append([event])
            }
            clusterEnd = max(clusterEnd, spans[event].1)
        }
        closeCluster()

        return slots.map { $0! }
    }
}
