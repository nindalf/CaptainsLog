import SwiftUI

/// One month of days in weeks starting on the user's first weekday. Without `allowsPast`, days
/// before today can't be picked and the chevrons never step back past the current month.
struct MonthGrid: View {
    @Binding var month: Date
    let selected: Date?
    let today: Date
    let allowsPast: Bool
    let onPick: (Date) -> Void

    private let calendar = Calendar.current

    private var currentMonth: Date {
        calendar.dateInterval(of: .month, for: today)?.start ?? today
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Six weeks, so the popover keeps its height from month to month. Nil pads either end.
    private var weeks: [[Date?]] {
        let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        cells += (0..<dayCount).map { calendar.date(byAdding: .day, value: $0, to: month) }
        cells += Array(repeating: nil, count: max(0, 42 - cells.count))
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if allowsPast || month > currentMonth {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain)
                        .help("Previous Month")
                }
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                    .help("Next Month")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)

            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    ForEach(weekdaySymbols.indices, id: \.self) { index in
                        Text(weekdaySymbols[index])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 30)
                    }
                }
                ForEach(weeks.indices, id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { weekday in
                            dayCell(weeks[week][weekday])
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        if let date {
            let isSelected = selected.map { calendar.isDate($0, inSameDayAs: date) } ?? false
            let isPast = !allowsPast && date < today
            let isToday = calendar.isDate(date, inSameDayAs: today)
            Button { onPick(date) } label: {
                Text("\(calendar.component(.day, from: date))")
                    .font(.callout.weight(isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .frame(width: 30, height: 24)
                    .foregroundStyle(isSelected ? Color.white : isPast ? Color.secondary.opacity(0.5) : isToday ? Color.accentColor : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.accentColor : .clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isPast)
        } else {
            Color.clear
                .frame(width: 30, height: 24)
        }
    }

    private func step(_ months: Int) {
        month = calendar.date(byAdding: .month, value: months, to: month) ?? month
    }
}
