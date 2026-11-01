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
                            NavigationRow(value: interview) {
                                row(interview)
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
                ContentUnavailableView("No Interviews", systemImage: "person.badge.clock")
            }
        }
        .navigationTitle("Interviews")
        .deleteConfirmation($pendingDelete)
    }

    private func header(_ group: MonthGroup) -> some View {
        let completed = group.interviews.count { $0.date <= .now }
        let scheduled = group.interviews.count - completed
        let summary = [
            completed > 0 ? "\(completed) completed" : nil,
            scheduled > 0 ? "\(scheduled) scheduled" : nil,
        ].compactMap { $0 }.joined(separator: ", ")
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(group.label).font(.title3.bold())
            Text(summary).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .padding(.horizontal, 4)
        .background(.background)
    }

    // Plain text for the co-interviewer, not PersonLinks -- the whole row is already a
    // NavigationLink label, and a nested link makes hit-testing ambiguous.
    private func row(_ interview: Interview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(interview.candidateName).font(.headline)
                Spacer()
                if let rec = interview.recommendation {
                    Text(rec.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(recommendationColor(rec).opacity(0.2))
                        .foregroundStyle(recommendationColor(rec))
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 6) {
                Text(DateLabel.dayTime(interview.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let role = interview.role {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let coInterviewer = interview.coInterviewer {
                    Label(coInterviewer.name, systemImage: "person.2")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func recommendationColor(_ rec: Recommendation) -> Color {
        switch rec {
        case .strongYes: .green
        case .yes: .blue
        case .no: .orange
        case .definitelyNot: .red
        }
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
