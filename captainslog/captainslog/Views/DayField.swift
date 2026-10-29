import SwiftUI
import CaptainsLogKit

/// A date-only field for things that already happened (a debrief, feedback): its `DateLabel`, or
/// "Not set", opening a popover of Today, Yesterday and a month grid. A picked day keeps the old
/// time of day, or now's, so same-day records still sort.
struct DayField: View {
    @Binding var date: Date?
    /// Offers Clear when set; off for dates that can't be empty.
    var clearable = true

    @State private var isPicking = false

    var body: some View {
        Button { isPicking = true } label: {
            Text(date.map { DateLabel.day($0) } ?? "Not set")
                .foregroundStyle(date == nil ? .secondary : .primary)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $isPicking) {
            DayPopover(selected: date, clearable: clearable) { picked in
                date = picked.map(keepingTime)
                isPicking = false
            }
        }
    }

    private func keepingTime(_ day: Date) -> Date {
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute, .second], from: date ?? .now)
        return cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
    }
}

extension DayField {
    /// For a date that's always set.
    init(date: Binding<Date>) {
        self.init(date: Binding(get: { date.wrappedValue }, set: { if let new = $0 { date.wrappedValue = new } }), clearable: false)
    }
}

private struct DayPopover: View {
    let selected: Date?
    let clearable: Bool
    /// The start of the picked day, or nil for Clear.
    let onPick: (Date?) -> Void

    @State private var month: Date

    private let calendar = Calendar.current

    init(selected: Date?, clearable: Bool, onPick: @escaping (Date?) -> Void) {
        self.selected = selected
        self.clearable = clearable
        self.onPick = onPick
        let cal = Calendar.current
        let shown = selected ?? .now
        _month = State(initialValue: cal.dateInterval(of: .month, for: shown)?.start ?? cal.startOfDay(for: shown))
    }

    private var today: Date { calendar.startOfDay(for: .now) }
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: today) ?? today }
    private var selectedDay: Date? { selected.map(calendar.startOfDay(for:)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            choiceRow("Today", day: today)
            choiceRow("Yesterday", day: yesterday)
            MonthGrid(month: $month, selected: selectedDay, today: today, allowsPast: true) { onPick($0) }
                .padding(.vertical, 6)
            if clearable, selected != nil {
                Divider()
                    .padding(.vertical, 4)
                Button { onPick(nil) } label: {
                    Text("Clear")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: 250)
    }

    private func choiceRow(_ title: String, day: Date) -> some View {
        Button { onPick(day) } label: {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selectedDay == day ? Color.accentColor.opacity(0.25) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

