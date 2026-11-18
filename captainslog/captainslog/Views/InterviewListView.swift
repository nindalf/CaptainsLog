import SwiftUI
import SwiftData
import CaptainsLogKit

struct InterviewListView: View {
    @Query(sort: \Interview.date, order: .reverse)
    private var interviews: [Interview]
    @State private var pendingDelete: DeletableRecord?

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
                            NavigationRow(value: interview, isPadded: false) {
                                InterviewRecordRow(interview: interview, date: .dayTime(interview.date))
                            }
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
        .overlay {
            if interviews.isEmpty {
                ContentUnavailableView("No Interviews", systemImage: RecordKind.interview.icon)
            }
        }
        .navigationTitle("Interviews")
        .deleteConfirmation($pendingDelete)
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
