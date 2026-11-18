import SwiftUI
import SwiftData
import CaptainsLogKit

struct InterviewListView: View {
    @Query(sort: \Interview.date, order: .reverse)
    private var interviews: [Interview]
    @State private var pendingDelete: DeletableRecord?
    @State private var selectedID: UUID?
    @FocusState private var listFocused: Bool
    @Environment(Navigator.self) private var navigator

    private var monthGroups: [MonthGroup] {
        let cal = Calendar.current
        // The @Query already sorts date-descending and Dictionary(grouping:) preserves
        // relative order, so the groups need no inner re-sort.
        let grouped = Dictionary(grouping: interviews) { interview in
            cal.date(from: cal.dateComponents([.year, .month], from: interview.date))
                ?? interview.date
        }
        return grouped.keys.sorted(by: >).map { MonthGroup(month: $0, interviews: grouped[$0]!) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(monthGroups) { group in
                    Section {
                        ForEach(group.interviews) { interview in
                            InterviewRecordRow(interview: interview, date: .dayTime(interview.date), isSelected: selectedID == interview.id)
                                .onRecordClick(select: { selectedID = interview.id }, open: { open(interview) })
                            .contextMenu {
                                Button("Delete Interview…", systemImage: "trash", role: .destructive) {
                                    pendingDelete = .interview(interview)
                                }
                            }
                        }
                    } header: {
                        header(group)
                    }
                }
            }
            .contentColumn()
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onAppear { DispatchQueue.main.async { listFocused = true } }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in moveSelection(by: 1); return .handled }
        .onKeyPress(.return, phases: .down) { _ in openSelected() }
        .selectionCommands(selectionCommands, claimsOnAppear: true, selection: selectedID) { listFocused = true }
        .overlay {
            if interviews.isEmpty {
                ContentUnavailableView("No Interviews", systemImage: RecordKind.interview.icon)
            }
        }
        .navigationTitle("Interviews")
        .deleteConfirmation($pendingDelete)
    }

    private var selectedInterview: Interview? {
        interviews.first { $0.id == selectedID }
    }

    private var selectionCommands: CommandHandlers {
        var handlers = CommandHandlers()
        if let interview = selectedInterview {
            handlers[.delete] = { pendingDelete = .interview(interview) }
        }
        return handlers
    }

    /// In the order on screen: the groups are newest month first, as the query sorts.
    private func moveSelection(by delta: Int) {
        selectedID = movedSelection(selectedID, by: delta, in: interviews.map(\.id))
    }

    private func openSelected() -> KeyPress.Result {
        guard let interview = selectedInterview else { return .ignored }
        open(interview)
        return .handled
    }

    private func open(_ interview: Interview) {
        selectedID = interview.id
        navigator.openInterview(interview)
    }

    private func header(_ group: MonthGroup) -> some View {
        SectionHeader(title: group.label, count: group.interviews.count).pinnedSectionHeader()
    }
}

private struct MonthGroup: Identifiable {
    let month: Date
    let interviews: [Interview]

    var id: Date { month }

    var label: String {
        if Calendar.current.isDate(month, equalTo: .now, toGranularity: .year) {
            return month.formatted(.dateTime.month(.wide))
        }
        return month.formatted(.dateTime.month(.wide).year())
    }
}

#Preview {
    NavigationStack {
        InterviewListView()
    }
    .previewEnvironment()
}
