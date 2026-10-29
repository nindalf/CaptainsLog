import Foundation
import SwiftData

extension Interview {
    /// Deletes the interview for good. Its calendar event is hidden rather than kept visible, since
    /// sync would otherwise grow a fresh stub on it. Linked todos stay, unlinked.
    public func delete(in context: ModelContext) {
        calendarEvent?.isHidden = true
        context.delete(self)
    }
}
