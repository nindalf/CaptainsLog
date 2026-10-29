import SwiftUI
import SwiftData
import CaptainsLogKit

/// Reopens todos, asking first when any was completed before today (`Todo.reopenNeedsConfirmation`).
/// Set `pending` through `request(_:)`; the alert shows while it is non-empty.
struct ReopenConfirmation: ViewModifier {
    @Binding var pending: [Todo]
    @Environment(\.modelContext) private var modelContext

    private var title: String {
        if pending.count == 1, let todo = pending.first { return "Reopen \"\(todo.title)\"?" }
        return "Reopen \(pending.count) to-dos?"
    }

    private var message: String {
        if pending.count == 1, let date = pending.first?.completedDate {
            let day = Calendar.current.isDateInYesterday(date) ? "yesterday" : "on \(DateLabel.header(date))"
            return "It was completed \(day). Completing it again will date it today."
        }
        return "Completing them again will date them today, not the day they were done."
    }

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: Binding(get: { !pending.isEmpty }, set: { if !$0 { pending = [] } })
        ) {
            Button("Reopen") {
                Self.reopen(pending, in: modelContext)
                pending = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }

    /// Reopens at once when every todo was completed today, else queues them for the alert.
    static func request(_ todos: [Todo], pending: inout [Todo], in context: ModelContext) {
        if Todo.reopenNeedsConfirmation(todos) {
            pending = todos
        } else {
            reopen(todos, in: context)
        }
    }

    private static func reopen(_ todos: [Todo], in context: ModelContext) {
        todos.forEach { $0.reopen() }
        try? context.save()
    }
}

extension View {
    func reopenConfirmation(_ pending: Binding<[Todo]>) -> some View {
        modifier(ReopenConfirmation(pending: pending))
    }
}
