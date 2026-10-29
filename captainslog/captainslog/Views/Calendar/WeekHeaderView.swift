import SwiftUI

struct WeekHeaderView: View {
    let weekStart: Date
    let dayCount: Int
    let onPrevWeek: () -> Void
    let onNextWeek: () -> Void
    let onToday: () -> Void

    private let calendar = Calendar.current

    private var weekEnd: Date {
        calendar.date(byAdding: .day, value: dayCount - 1, to: weekStart)!
    }

    var body: some View {
        VStack(spacing: 2) {
            navigationRow
            dayLabelsRow
        }
        .padding(.vertical, 4)
        .background(.bar)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var navigationRow: some View {
        HStack {
            HStack(spacing: 12) {
                Button { onPrevWeek() } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                Button("Today") { onToday() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Button { onNextWeek() } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            Text(weekRangeLabel)
                .font(.headline)
        }
        .padding(.horizontal, 12)
    }

    private var dayLabelsRow: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: TimeGridConstants.gutterWidth)

            ForEach(0..<dayCount, id: \.self) { offset in
                dayLabel(offset: offset)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayLabel(offset: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
        let isToday = calendar.isDateInToday(date)

        return VStack(spacing: 1) {
            Text(date, format: .dateTime.weekday(.narrow))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(date, format: .dateTime.day())
                .font(.caption.bold())
                .foregroundStyle(isToday ? .white : .primary)
                .frame(width: 22, height: 22)
                .background(isToday ? Color.accentColor : .clear, in: Circle())
        }
    }

    private var weekRangeLabel: String {
        let startDay = calendar.component(.day, from: weekStart)
        let endDay = calendar.component(.day, from: weekEnd)
        let month = weekEnd.formatted(.dateTime.month(.wide))
        let year = weekEnd.formatted(.dateTime.year())

        let startMonth = weekStart.formatted(.dateTime.month(.abbreviated))
        let endMonth = weekEnd.formatted(.dateTime.month(.abbreviated))

        if startMonth == endMonth {
            return "\(startDay) - \(endDay) \(month) \(year)"
        }
        return "\(startDay) \(startMonth) - \(endDay) \(endMonth) \(year)"
    }
}
