import SwiftUI
import SwiftData
import AppKit
import CaptainsLogKit

struct InterviewDetailView: View {
    @Bindable var interview: Interview
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // Every todo ever filed against the interview, trashed ones too, so the scorecard todo
    // comes back neither after it is deleted nor after the notes are cleared and retyped.
    @Query private var linkedTodos: [Todo]
    @Query(filter: #Predicate<Todo> { $0.completedDate == nil }) private var openTodos: [Todo]

    init(interview: Interview) {
        self.interview = interview
        let id = interview.id
        _linkedTodos = Query(filter: #Predicate<Todo> { $0.interview?.id == id })
    }
    @State private var showCopyConfirmation = false
    @State private var todoAddTick = 0
    @State private var pendingDelete: DeletableRecord?

    private struct ScorecardTheme {
        let upside: String
        let risk: String
    }

    private static let scorecardThemes: [ScorecardTheme] = [
        .init(upside: "Is able to reason from first principles", risk: "Did not reason from first principles"),
        .init(upside: "Arrives at a working solution", risk: "Did not arrive at a working solution"),
        .init(upside: "Makes independent progress", risk: "Did not make independent progress"),
        .init(upside: "Works iteratively and is unafraid to make changes", risk: "Did not work iteratively or was reluctant to make changes"),
        .init(upside: "Focuses on the core problem", risk: "Did not focus on the core problem"),
        .init(upside: "Reasons effectively about edge cases & partial failure", risk: "Did not reason effectively about edge cases & partial failure"),
        .init(upside: "Reasons about tradeoffs", risk: "Did not reason about tradeoffs"),
        .init(upside: "Asked clarifying questions", risk: "Did not ask clarifying questions"),
    ]

    private static let canonicalKeyBlock = """
        ## Key

        + = Something good
        - = Something not so good
        ! = Where is this going?
        H = Helpful hint from interviewer
        Q = Question from interviewer
        C = Clarification
        """

    var body: some View {
        DetailPage {
            DetailHeader(title: $interview.candidateName, placeholder: "Candidate") {
                // The calendar event owns the date.
                Text(DateLabel.dayTime(interview.date))
                if let coInterviewer = interview.coInterviewer {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                        PersonLinks(people: [coInterviewer])
                    }
                }
                LinkMetadataItem(title: "Whiteboard", prompt: "Link to the whiteboard", urlString: $interview.whiteboardLink)
            }

            DetailProperties {
                DetailTextProperty(label: "Role", prompt: "Add role", text: $interview.role)
                DetailTextProperty(label: "Problem", prompt: "Add problem", text: $interview.problemName)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.top, -12)

            LinkedTodoList(interview: interview, addTick: todoAddTick)

            rawNotesSection
            scorecardSection

            DetailSection("Conclusion") {
                HStack {
                    Spacer()
                    copyButton { copyMarkdownForSlack(interview.conclusion ?? "") }
                }
                .padding(.bottom, 4)
                MarkdownEditor(
                    text: Binding(
                        get: { interview.conclusion ?? "" },
                        set: { interview.conclusion = $0.isEmpty ? nil : $0 }
                    ),
                    minHeight: 60,
                    showSlackControls: false
                )
            }

            DetailSection("Debrief") {
                DayField(date: $interview.debriefDate)
            } content: {
                MarkdownEditor(
                    text: Binding(
                        get: { interview.debriefNotes ?? "" },
                        set: { interview.debriefNotes = $0.isEmpty ? nil : $0 }
                    ),
                    minHeight: 60,
                    copyHelp: "Copy"
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button { todoAddTick += 1 } label: {
                    Label("Add Todo", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            // The eye, as at the bottom right of every card, then the trash.
            ToolbarItem {
                PrivacyEye(isOn: $interview.isPrivate, inToolbar: true)
            }
            ToolbarItem {
                Button { pendingDelete = .interview(interview) } label: {
                    Label("Delete Interview…", systemImage: "trash")
                }
                .help("Delete Interview")
            }
        }
        .deleteConfirmation($pendingDelete) { _ in dismiss() }
        .onChange(of: interview.hasWrittenText) { hadText, _ in addScorecardTodoIfDue(hadText: hadText) }
    }

    private var rawNotesSection: some View {
        DetailSection("Raw Notes") {
            // Where the other notes boxes keep their Slack controls.
            HStack {
                Spacer()
                Button {
                    copyNotes()
                } label: {
                    Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(showCopyConfirmation ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy")
            }
            .font(.caption)
            .padding(.bottom, 4)
            MarkdownEditor(text: notesBinding, minHeight: 200, showSlackControls: false)
        }
    }

    private var scorecardSection: some View {
        DetailSection("Scorecard") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Themes").font(.body.weight(.semibold))
                    ForEach(Self.scorecardThemes, id: \.upside) { theme in
                        themeRow(theme)
                    }
                }

                scorecardField("Upsides", \.upsides)
                scorecardField("Risk Factors", \.riskFactors)

                DetailProperties(font: .body, prominentLabels: true) {
                    DetailTextProperty(label: "Level", prompt: "Add level assessment", text: $interview.levelAssessment)
                    DetailProperty(label: "Recommendation") {
                        Picker("Recommendation", selection: $interview.recommendation) {
                            Text("None").tag(Recommendation?.none)
                            ForEach(Recommendation.allCases, id: \.self) { r in
                                Text(r.rawValue).tag(Recommendation?.some(r))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
        }
    }

    private func themeRow(_ theme: ScorecardTheme) -> some View {
        let inUpsides = (interview.upsides ?? "").contains("_\(theme.upside)_")
        let inRisks = (interview.riskFactors ?? "").contains("_\(theme.risk)_")
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button {
                appendTheme(theme.upside, to: \.upsides)
            } label: {
                Image(systemName: inUpsides ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .disabled(inUpsides)
            .help("Add to upsides")
            Button {
                appendTheme(theme.risk, to: \.riskFactors)
            } label: {
                Image(systemName: inRisks ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .disabled(inRisks)
            .help("Add to risk factors")
            Text(theme.upside)
                .font(.body)
                .foregroundStyle(inUpsides || inRisks ? .tertiary : .primary)
                .padding(.leading, 4)
            Spacer()
        }
        .font(.title3)
    }

    private func copyButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .help("Copy")
    }

    private func scorecardField(_ title: String, _ keyPath: ReferenceWritableKeyPath<Interview, String?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).font(.body.weight(.semibold))
                copyButton { copyMarkdownForSlack(interview[keyPath: keyPath] ?? "") }
            }
            MarkdownEditor(
                text: Binding(
                    get: { interview[keyPath: keyPath] ?? "" },
                    set: { interview[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
                ),
                minHeight: 40,
                showSlackControls: false
            )
        }
    }

    // MARK: - Scorecard helpers

    private func addScorecardTodoIfDue(hadText: Bool) {
        guard ScorecardTodo.isDue(hadText: hadText, interview: interview, linkedTodos: linkedTodos) else { return }
        let todo = ScorecardTodo.make(for: interview, among: openTodos)
        modelContext.insert(todo)
        todo.interview = interview
        try? modelContext.save()
    }

    private func appendTheme(_ theme: String, to keyPath: ReferenceWritableKeyPath<Interview, String?>) {
        let bullet = "- _\(theme)_"
        let current = interview[keyPath: keyPath] ?? ""
        interview[keyPath: keyPath] = current.isEmpty ? bullet : current + "\n" + bullet
    }

    // MARK: - Notes helpers

    private var notesText: String {
        Self.stripKeyHeader(interview.rawNotes ?? "")
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { notesText },
            set: { interview.rawNotes = $0.isEmpty ? nil : $0 }
        )
    }

    private func copyNotes() {
        let notes = notesText
        let full = Self.canonicalKeyBlock + "\n\n" + notes
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full, forType: .string)
        showCopyConfirmation = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showCopyConfirmation = false
        }
    }

    private static func stripKeyHeader(_ text: String) -> String {
        guard text.hasPrefix("## Key") else { return text }
        let lines = text.components(separatedBy: "\n")
        let keyChars: Set<Character> = ["+", "-", "!", "H", "Q", "C"]
        var endIndex = 0
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("## Key") {
                endIndex = i + 1
                continue
            }
            if let first = trimmed.first, keyChars.contains(first), trimmed.dropFirst().hasPrefix(" = ") {
                endIndex = i + 1
                continue
            }
            break
        }
        while endIndex < lines.count && lines[endIndex].trimmingCharacters(in: .whitespaces).isEmpty {
            endIndex += 1
        }
        let remaining = lines[endIndex...].joined(separator: "\n")
        return remaining
    }

}

#Preview {
    NavigationStack {
        InterviewDetailView(interview: PreviewData.makeInterview())
    }
    .previewEnvironment()
}
