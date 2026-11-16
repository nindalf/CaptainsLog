import SwiftUI
import SwiftData
import CaptainsLogKit

/// A log entry's day: Today, Yesterday, then a month calendar. Changes only the day; the entry
/// keeps its time of day.
struct LogDatePopover: View {
    @Bindable var entry: LogEntry

    @Environment(\.dismiss) private var dismiss
    /// First day of the month the calendar shows.
    @State private var month: Date

    private let calendar = Calendar.current

    init(entry: LogEntry) {
        self.entry = entry
        let cal = Calendar.current
        _month = State(initialValue: cal.dateInterval(of: .month, for: entry.timestamp)?.start ?? cal.startOfDay(for: entry.timestamp))
    }

    private var today: Date { calendar.startOfDay(for: .now) }
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: today) ?? today }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            choiceRow("Today", systemImage: "star.fill", tint: .yellow, day: today)
            choiceRow("Yesterday", systemImage: "moon.fill", tint: .indigo, day: yesterday)
            MonthGrid(month: $month, selected: entry.timestamp, today: today, allowsPast: true, onPick: choose)
                .padding(.vertical, 6)
        }
        .padding(10)
        .frame(width: 250)
    }

    private func choiceRow(_ title: String, systemImage: String, tint: Color, day: Date) -> some View {
        Button { choose(day) } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(calendar.isDate(entry.timestamp, inSameDayAs: day) ? Color.accentColor.opacity(0.25) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ day: Date) {
        entry.move(toDay: day, calendar: calendar)
        // A draft has no context yet and saves when committed.
        try? entry.modelContext?.save()
        dismiss()
    }
}
