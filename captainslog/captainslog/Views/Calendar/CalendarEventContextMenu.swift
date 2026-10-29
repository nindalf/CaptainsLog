import SwiftUI
import SwiftData
import CaptainsLogKit

/// Hide and Delete on right-click. A tap on an event with a meeting or interview opens it
/// instead of the popover, so this is the only way to remove those.
struct CalendarEventContextMenu: ViewModifier {
    let event: CalendarEvent

    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Hide Event", systemImage: "eye.slash") {
                event.isHidden = true
                try? modelContext.save()
            }
            Button(deleteTitle, systemImage: "trash", role: .destructive) {
                event.deleteWithEmptyStubs(in: modelContext)
                try? modelContext.save()
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
