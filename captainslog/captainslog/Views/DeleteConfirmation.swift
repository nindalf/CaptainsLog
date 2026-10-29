import SwiftUI
import SwiftData
import CaptainsLogKit

/// A record that deletes for good, after a confirmation. Todos have the Trash instead; PRs mirror
/// GitHub, so sync would bring them back.
enum DeletableRecord {
    case log(LogEntry)
    case meeting(Meeting)
    case interview(Interview)

    var id: UUID {
        switch self {
        case .log(let entry): entry.id
        case .meeting(let meeting): meeting.id
        case .interview(let interview): interview.id
        }
    }

    fileprivate var title: String {
        switch self {
        case .log(let entry): "Delete \"\(entry.title)\"?"
        case .meeting(let meeting): "Delete \"\(meeting.title)\"?"
        case .interview(let interview): "Delete the interview with \(interview.candidateName)?"
        }
    }

    fileprivate var message: String {
        switch self {
        case .log: "This can't be undone."
        case .meeting: "This can't be undone. Its todos and calendar event are kept."
        case .interview(let interview) where interview.calendarEvent != nil:
            "This can't be undone. Its todos are kept, and its calendar event is hidden so sync doesn't bring it back."
        case .interview: "This can't be undone. Its todos are kept."
        }
    }

    fileprivate func delete(in context: ModelContext) {
        switch self {
        case .log(let entry): context.delete(entry)
        case .meeting(let meeting): context.delete(meeting)
        case .interview(let interview): interview.delete(in: context)
        }
    }
}

/// Asks before deleting. The alert shows while `pending` is set; `onDelete` runs just before the
/// delete, so a host showing the record can let go of it first.
struct DeleteConfirmation: ViewModifier {
    @Binding var pending: DeletableRecord?
    var onDelete: (DeletableRecord) -> Void
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.alert(
            pending?.title ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { record in
            Button("Delete", role: .destructive) {
                onDelete(record)
                record.delete(in: modelContext)
                try? modelContext.save()
                pending = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: { record in
            Text(record.message)
        }
    }
}

extension View {
    func deleteConfirmation(_ pending: Binding<DeletableRecord?>, onDelete: @escaping (DeletableRecord) -> Void = { _ in }) -> some View {
        modifier(DeleteConfirmation(pending: pending, onDelete: onDelete))
    }
}
