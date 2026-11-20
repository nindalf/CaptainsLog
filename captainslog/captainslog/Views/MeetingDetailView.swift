import SwiftUI
import SwiftData
import CaptainsLogKit

struct MeetingDetailView: View {
    @Bindable var meeting: Meeting
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @State private var todoAddTick = 0
    @State private var pendingDelete: DeletableRecord?
    /// Notes fields shown with their editor. Empty ones show an Add row until added, and a field
    /// stays shown once it is, so clearing it while typing doesn't hide it.
    @State private var shownNotes: Set<NotesField> = []
    @FocusState private var focusedNotes: NotesField?
    /// After the meeting goes into a project, the rest of its series that could follow it.
    @State private var seriesOffer: SeriesOffer?

    private struct SeriesOffer {
        let project: Project
        let meetings: [Meeting]
    }

    private enum NotesField: Hashable, CaseIterable {
        case prepNotes, notes, summary

        var keyPath: ReferenceWritableKeyPath<Meeting, String?> {
            switch self {
            case .prepNotes: \.prepNotes
            case .notes: \.notes
            case .summary: \.summary
            }
        }

        var title: String {
            switch self {
            case .prepNotes: "Prep Notes"
            case .notes: "Notes"
            case .summary: "Summary"
            }
        }
    }

    /// Before the meeting the prep comes first; after it, what came out of it.
    private var notesOrder: [NotesField] {
        meeting.date > .now ? [.prepNotes, .notes, .summary] : [.summary, .notes, .prepNotes]
    }

    var body: some View {
        DetailPage {
            DetailHeader(title: $meeting.title) {
                // The calendar event owns the date.
                Text(DateLabel.dayTime(meeting.date))
                if let url = meeting.calendarEvent?.meetingURL {
                    Link(destination: url) { Label("Join", systemImage: "video") }
                        .help(url.absoluteString)
                }
                LinkMetadataItem(title: "Slack", prompt: "Link to the shared notes", urlString: slackURL)
                ProjectMetadataItem(current: meeting.project, projects: projects) { pickProject($0) }
            }
            if !meeting.attendees.isEmpty {
                PersonLinks(people: meeting.attendees.sorted { $0.name < $1.name })
                    .font(.callout)
                    .padding(.top, -16)
            }

            LinkedTodoList(meeting: meeting, addTick: todoAddTick)

            ForEach(notesOrder.filter(isShown), id: \.self) { field in
                notesSection(field)
            }
            let hidden = notesOrder.filter { !isShown($0) }
            if !hidden.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 18) {
                        ForEach(hidden, id: \.self) { field in
                            // Styled like LinkedTodoList's Add Todo row.
                            Button("Add \(field.title.lowercased())", systemImage: "plus") {
                                shownNotes.insert(field)
                                // The editor only exists after this update, so focus it on the next one.
                                Task { focusedNotes = field }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    if let prepCommand {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Or have Claude Code draft the prep notes:")
                                .foregroundStyle(.secondary)
                            CommandBox(command: prepCommand)
                                .frame(maxWidth: 560)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            SeriesHistorySection(meeting: meeting)
        }
        .onChange(of: meeting.id, initial: true) {
            shownNotes = Set(NotesField.allCases.filter(hasText))
        }
        .toolbar {
            ToolbarItem {
                Button { todoAddTick += 1 } label: {
                    Label("Add Todo", systemImage: "plus")
                }
                .help(AppCommand.newTodo.help("Add Todo"))
            }
            // The eye, as at the bottom right of every card, then the trash.
            ToolbarItem {
                PrivacyEye(isOn: $meeting.isPrivate, inToolbar: true)
            }
            ToolbarItem {
                Button { pendingDelete = .meeting(meeting) } label: {
                    Label("Delete Meeting…", systemImage: "trash")
                }
                .help("Delete Meeting")
            }
        }
        .deleteConfirmation($pendingDelete) { _ in dismiss() }
        .pageCommands(pageCommands)
        .confirmationDialog(
            "Add the whole series to \(seriesOffer?.project.name ?? "the project")?",
            isPresented: Binding(get: { seriesOffer != nil }, set: { if !$0 { seriesOffer = nil } }),
            presenting: seriesOffer
        ) { offer in
            Button("Add All \(offer.meetings.count + 1) Meetings") {
                offer.meetings.forEach { $0.project = offer.project }
            }
            Button("Only This Meeting", role: .cancel) {}
        } message: { offer in
            Text(seriesMessage(offer))
        }
    }

    /// New Todo files one here; Join opens this meeting's link.
    private var pageCommands: CommandHandlers {
        var handlers = CommandHandlers()
        handlers[.newTodo] = { todoAddTick += 1 }
        handlers[.delete] = { pendingDelete = .meeting(meeting) }
        if let url = meeting.calendarEvent?.meetingURL {
            handlers[.join] = { NSWorkspace.shared.open(url) }
        }
        return handlers
    }

    /// Puts the meeting in `project`, then offers to do the same for the rest of its series.
    private func pickProject(_ project: Project?) {
        meeting.project = project
        guard let project, let others = try? meeting.seriesMeetings(in: modelContext) else { return }
        let moving = others.filter { $0.project?.id != project.id }
        guard !moving.isEmpty else { return }
        // After the popover has closed, or the dialog can be lost with it.
        Task { seriesOffer = SeriesOffer(project: project, meetings: moving) }
    }

    private func seriesMessage(_ offer: SeriesOffer) -> String {
        let count = offer.meetings.count
        var text = "\(count) other meeting\(count == 1 ? "" : "s") in this recurring series \(count == 1 ? "isn't" : "aren't") in \(offer.project.name)."
        let elsewhere = offer.meetings.filter { $0.project != nil }.count
        if elsewhere > 0 {
            text += elsewhere == 1 ? " One is in another project, and would move." : " \(elsewhere) are in other projects, and would move."
        }
        return text
    }

    private var slackURL: Binding<String?> {
        Binding(
            get: { meeting.slackURL?.absoluteString },
            set: { meeting.slackURL = $0.flatMap(URL.init(string:)) }
        )
    }

    /// The meeting-prep skill's command for this meeting, until a notes field is opened and while the
    /// skill can find it: an event `events list --upcoming --meetings` lists (a meeting, within its week,
    /// not withheld as an outside invitation, whose title the command would hand the agent).
    private var prepCommand: String? {
        guard !(settings.hidesOutsideInvitations && meeting.isWithheldFromAgents) else { return nil }
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: .now))!
        guard !NotesField.allCases.contains(where: isShown), let event = meeting.calendarEvent, event.isMeeting,
              event.startTime > .now, event.startTime < weekEnd else { return nil }
        return "/meeting-prep \(event.title), \(DateLabel.dayTime(event.startTime))"
    }

    private func hasText(_ field: NotesField) -> Bool {
        !(meeting[keyPath: field.keyPath] ?? "").isEmpty
    }

    private func isShown(_ field: NotesField) -> Bool {
        shownNotes.contains(field) || hasText(field)
    }

    private func notesSection(_ field: NotesField) -> some View {
        DetailSection(field.title) {
            MarkdownEditor(
                text: Binding(
                    get: { meeting[keyPath: field.keyPath] ?? "" },
                    set: { meeting[keyPath: field.keyPath] = $0.isEmpty ? nil : $0 }
                ),
                minHeight: 60,
                focus: $focusedNotes,
                focusValue: field
            )
        }
    }
}

#Preview {
    NavigationStack {
        MeetingDetailView(meeting: PreviewData.makeMeeting())
    }
    .previewEnvironment()
}
