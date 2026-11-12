import SwiftUI
import SwiftData
import CaptainsLogKit

/// Hide, Decline and Delete on right-click. A tap on an event with a meeting or interview opens it
/// instead of the popover, so this is the only way to remove those.
struct CalendarEventContextMenu: ViewModifier {
    let event: CalendarEvent

    @Environment(\.modelContext) private var modelContext
    @State private var confirmingDelete = false
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Hide Event", systemImage: "eye.slash") {
                    event.isHidden = true
                    try? modelContext.save()
                }
                switch CalendarEventRemoval.offered(for: event) {
                case .decline:
                    Button("Decline", systemImage: "xmark.circle") { remove(.decline) }
                case .delete:
                    Button(deleteTitle, systemImage: "trash", role: .destructive) { confirmingDelete = true }
                case nil:
                    EmptyView()
                }
            }
            .confirmationDialog(CalendarEventRemoval.deletePrompt(event), isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) { remove(.delete) }
            } message: {
                Text(CalendarEventRemoval.deleteMessage)
            }
            .alert("Couldn't change the event", isPresented: Binding { error != nil } set: { if !$0 { error = nil } }) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
    }

    private func remove(_ action: CalendarEventRemoval.Action) {
        Task {
            do {
                try await CalendarEventRemoval.write(action, to: event)
                event.deleteWithEmptyStubs(in: modelContext)
                try? modelContext.save()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private var deleteTitle: String {
        // An interview with notes outlives its event, so only name it when it goes too.
        event.interview?.isEmpty == true ? "Delete Event and Interview" : "Delete Event"
    }
}

extension View {
    func calendarEventContextMenu(_ event: CalendarEvent) -> some View {
        modifier(CalendarEventContextMenu(event: event))
    }
}
