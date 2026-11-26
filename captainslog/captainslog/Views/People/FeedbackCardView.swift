import SwiftUI
import CaptainsLogKit

/// The card a feedback row expands into: its text, then its day and privacy at the bottom right. Return is a
/// new line, since feedback is all body; Escape closes it.
struct FeedbackCardView: View {
    @Bindable var feedback: Feedback
    var focusedField: FocusState<UUID?>.Binding

    @State private var showDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkdownEditor(
                text: $feedback.content,
                placeholder: "Feedback for \(feedback.person.name)…",
                minHeight: 60,
                maxHeight: 300,
                showSlackControls: false,
                focus: focusedField,
                focusValue: feedback.id
            )
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                dateControl
                PrivacyEye(isOn: $feedback.isPrivate)
            }
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .recordCard()
        .contentShape(Rectangle())
        .onTapGesture { }
    }

    private var dateControl: some View {
        Button { showDate.toggle() } label: {
            if Calendar.current.isDateInToday(feedback.date) {
                Image(systemName: "calendar")
            } else {
                Text(DateLabel.day(feedback.date)).cardPill(.blue)
            }
        }
        .buttonStyle(.plain)
        .help("Date")
        .popover(isPresented: $showDate) {
            DayPopover(selected: feedback.date, clearable: false) { picked in
                if let picked { feedback.date = DayField.day(picked, keepingTimeOf: feedback.date) }
                showDate = false
            }
        }
    }
}
